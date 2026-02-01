#!/bin/bash
# WRF Automated Startup Script
# Reads configuration from GCE metadata and runs WRF simulation
set -euxo pipefail
exec > >(tee -a /var/log/wrf-startup.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

echo "=========================================="
echo "WRF Startup Script - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=========================================="

# -------------------------
# Read metadata
# -------------------------
METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
METADATA_HEADER="Metadata-Flavor: Google"

get_metadata() {
  curl -sf -H "${METADATA_HEADER}" "${METADATA_URL}/$1" || echo "$2"
}

WRF_RUN_MINUTES=$(get_metadata "wrf-run-minutes" "60")
WRF_CASE=$(get_metadata "wrf-case" "em_quarter_ss")
GCS_BUCKET=$(get_metadata "gcs-bucket" "")

echo "Configuration:"
echo "  WRF_RUN_MINUTES: ${WRF_RUN_MINUTES}"
echo "  WRF_CASE: ${WRF_CASE}"
echo "  GCS_BUCKET: ${GCS_BUCKET}"

if [ -z "${GCS_BUCKET}" ]; then
  echo "ERROR: gcs-bucket metadata not set"
  exit 1
fi

# -------------------------
# Setup variables
# -------------------------
TS="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname)"
WRF_OUTPUT_DIR="/opt/wrf_output"
WRF_BUILD_DIR="/opt/wrf_build"
DOCKERFILE_PATH="${WRF_BUILD_DIR}/Dockerfile"
IMAGE_NAME="wrf_ideal:${WRF_CASE}"
MARKER_FILE="/opt/.wrf_setup_complete"

mkdir -p "${WRF_OUTPUT_DIR}" "${WRF_BUILD_DIR}"
chmod -R 777 "${WRF_OUTPUT_DIR}"

# -------------------------
# Install dependencies (only on first boot)
# -------------------------
if [ ! -f "${MARKER_FILE}" ]; then
  echo "First boot: Installing dependencies..."
  
  apt-get update
  apt-get install -y \
    ca-certificates curl gnupg apt-transport-https \
    lsb-release docker.io

  systemctl enable --now docker
  
  # Install Google Cloud CLI
  if ! command -v gcloud &> /dev/null; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /etc/apt/keyrings/google-cloud.gpg
    echo "deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list
    apt-get update
    apt-get install -y google-cloud-cli
  fi
  
  echo "Dependencies installed."
fi

# -------------------------
# Build WRF Docker image (if not exists)
# -------------------------
if ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
  echo "Building WRF Docker image for case: ${WRF_CASE}..."
  
  cat > "${DOCKERFILE_PATH}" << 'DOCKERFILE_EOF'
FROM centos:7

# Fix CentOS 7 EOL mirror issues
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*.repo && \
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo

ENV WRF_VERSION 4.0.3

RUN yum -y update \
 && yum -y install file gcc gcc-gfortran gcc-c++ glibc.i686 libgcc.i686 libpng-devel jasper jasper-devel hostname m4 make perl \
    tar tcsh time wget which zlib zlib-devel openssh-clients openssh-server net-tools \
    epel-release fontconfig libgfortran libXext libXrender ImageMagick sudo

RUN yum -y install netcdf-devel.x86_64 netcdf-fortran-devel.x86_64 netcdf-fortran-openmpi-devel.x86_64 \
    hdf5.x86_64 hdf5-devel.x86_64 hdf5-openmpi.x86_64 hdf5-openmpi-devel.x86_64

RUN yum -y install openmpi openmpi-devel

ENV NETCDF /wrf/libs/netcdf
ENV PATH /usr/lib64/openmpi/bin:$PATH
ENV LD_LIBRARY_PATH /usr/lib64/openmpi/lib:$NETCDF/lib:$LD_LIBRARY_PATH

WORKDIR /wrf

RUN mkdir -p /wrf/libs/netcdf/lib && \
    mkdir -p /wrf/libs/netcdf/include && \
    ln -sf /usr/lib64/openmpi/lib/libnetcdff.so /wrf/libs/netcdf/lib/ && \
    ln -sf /usr/lib64/openmpi/lib/libnetcdf.so /wrf/libs/netcdf/lib/ && \
    ln -sf /usr/include/openmpi-x86_64/* /wrf/libs/netcdf/include/ && \
    ln -sf /usr/lib64/openmpi/lib/* /wrf/libs/netcdf/lib/

RUN curl -SL https://github.com/wrf-model/WRF/archive/v${WRF_VERSION}.tar.gz | tar zxC /wrf \
    && mv /wrf/WRF-${WRF_VERSION} /wrf/WRF

WORKDIR /wrf/WRF

RUN printf '34\n1\n' | ./configure

ARG WRF_CASE=em_quarter_ss
RUN ./compile ${WRF_CASE} 2>&1 | tee compile.log

RUN ls -la /wrf/WRF/main/ideal.exe /wrf/WRF/main/wrf.exe

CMD ["/bin/bash"]
DOCKERFILE_EOF

  docker build \
    --build-arg WRF_CASE="${WRF_CASE}" \
    -t "${IMAGE_NAME}" \
    "${WRF_BUILD_DIR}"
  
  echo "Docker image built: ${IMAGE_NAME}"
  touch "${MARKER_FILE}"
else
  echo "Docker image already exists: ${IMAGE_NAME}"
fi

# -------------------------
# Run WRF simulation
# -------------------------
echo "Starting WRF simulation..."
echo "  Case: ${WRF_CASE}"
echo "  Duration: ${WRF_RUN_MINUTES} minutes"

RUN_ID="${TS}-${WRF_CASE}-${WRF_RUN_MINUTES}min"
RUN_OUTPUT_DIR="${WRF_OUTPUT_DIR}/${RUN_ID}"
mkdir -p "${RUN_OUTPUT_DIR}"

docker run --rm \
  -v "${RUN_OUTPUT_DIR}:/output" \
  "${IMAGE_NAME}" \
  bash -c "
set -eux
cd /wrf/WRF/test/${WRF_CASE}

# Link data files
./run_me_first.csh || true

# Run ideal.exe to generate initial conditions
./ideal.exe

# Modify namelist for custom run duration
sed -i 's/run_minutes.*=.*/run_minutes = ${WRF_RUN_MINUTES},/' namelist.input

# Show configuration
echo '=== Namelist Configuration ==='
grep -E 'run_|time_step|history_interval' namelist.input

# Run WRF
echo '=== Starting WRF ==='
START_TIME=\$(date +%s)
./wrf.exe
END_TIME=\$(date +%s)
ELAPSED=\$((END_TIME - START_TIME))
echo \"WRF completed in \${ELAPSED} seconds\"

# Copy outputs
cp -v wrfout* wrfinput* namelist.input rsl.* /output/ 2>/dev/null || true
echo \${ELAPSED} > /output/elapsed_seconds.txt
"

# -------------------------
# Upload to GCS
# -------------------------
echo "Uploading results to GCS..."
GCS_PATH="gs://${GCS_BUCKET}/runs/${RUN_ID}/"

gsutil -m cp -r "${RUN_OUTPUT_DIR}/*" "${GCS_PATH}"

# Create a summary file
cat > "${RUN_OUTPUT_DIR}/summary.json" << EOF
{
  "run_id": "${RUN_ID}",
  "timestamp": "${TS}",
  "hostname": "${HOST}",
  "wrf_case": "${WRF_CASE}",
  "run_minutes": ${WRF_RUN_MINUTES},
  "gcs_path": "${GCS_PATH}",
  "elapsed_seconds": $(cat "${RUN_OUTPUT_DIR}/elapsed_seconds.txt" 2>/dev/null || echo "null")
}
EOF

gsutil cp "${RUN_OUTPUT_DIR}/summary.json" "${GCS_PATH}"

echo "=========================================="
echo "WRF Simulation Complete!"
echo "Results: ${GCS_PATH}"
echo "=========================================="

# List outputs
gsutil ls -lh "${GCS_PATH}"
