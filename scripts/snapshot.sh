#!/bin/bash
#
# WebCode Snapshot Script (Layered Backup)
#
# Creates a complete snapshot using Docker layered storage:
# 1. Base image (land007/webcode:latest) - backed up once per version
# 2. Commit layer (user changes) - backed up each snapshot
# 3. Volumes (user data) - backed up each snapshot
#
# Usage: snapshot.sh [snapshot_name]
#   snapshot_name - optional, defaults to snapshot-YYYYMMDD-HHMMSS
#

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/backups}"
SNAPSHOT_NAME="${1:-snapshot-$(date +%Y%m%d-%H%M%S)}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MAX_SNAPSHOTS="${MAX_SNAPSHOTS:-3}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[snapshot]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[snapshot]${NC} $1"
}

error() {
    echo -e "${RED}[snapshot]${NC} $1"
}

info() {
    echo -e "${BLUE}[snapshot]${NC} $1"
}

# Create directories
mkdir -p "${BACKUP_DIR}/base-images"
mkdir -p "${BACKUP_DIR}/snapshots/${SNAPSHOT_NAME}"

log "Creating snapshot: ${SNAPSHOT_NAME}"
log "Backup directory: ${BACKUP_DIR}"

# Step 1: Detect base image
log "Detecting base image..."
CONTAINER_NAME="webcode"
if ! docker inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    error "Container '${CONTAINER_NAME}' not found"
    exit 1
fi

BASE_IMAGE=$(docker inspect "${CONTAINER_NAME}" -f '{{.Config.Image}}')
BASE_IMAGE_ID=$(docker inspect "${BASE_IMAGE}" -f '{{.Id}}' 2>/dev/null || echo "unknown")
BASE_IMAGE_SHORT_ID=$(echo "${BASE_IMAGE_ID}" | cut -d: -f2 | cut -c1-12)
BASE_IMAGE_FILE="webcode-base-${BASE_IMAGE_SHORT_ID}.tar.gz"

log "Base image: ${BASE_IMAGE}"
log "Base image ID: ${BASE_IMAGE_SHORT_ID}"

# Step 2: Backup base image (if not already backed up)
BASE_IMAGE_PATH="${BACKUP_DIR}/base-images/${BASE_IMAGE_FILE}"
if [ ! -f "${BASE_IMAGE_PATH}" ]; then
    log "Backing up base image: ${BASE_IMAGE} (${BASE_IMAGE_SHORT_ID})"
    docker save "${BASE_IMAGE}" | gzip > "${BASE_IMAGE_PATH}"

    if [ -f "${BASE_IMAGE_PATH}" ]; then
        BASE_IMAGE_SIZE=$(du -h "${BASE_IMAGE_PATH}" | cut -f1)
        log "Base image backed up: ${BASE_IMAGE_PATH} (${BASE_IMAGE_SIZE})"
    else
        error "Failed to backup base image"
        exit 1
    fi
else
    BASE_IMAGE_SIZE=$(du -h "${BASE_IMAGE_PATH}" | cut -f1)
    log "Base image already exists: ${BASE_IMAGE_PATH} (${BASE_IMAGE_SIZE})"
fi

# Step 3: Commit container as snapshot image
log "Committing container state..."
COMMIT_IMAGE_NAME="webcode-snapshot:${TIMESTAMP}"
docker commit "${CONTAINER_NAME}" "${COMMIT_IMAGE_NAME}"

if ! docker inspect "${COMMIT_IMAGE_NAME}" >/dev/null 2>&1; then
    error "Failed to commit container"
    exit 1
fi

log "Container committed as: ${COMMIT_IMAGE_NAME}"

# Step 4: Export commit layer (only new layers, not base image)
log "Exporting commit layer..."
LAYER_TAR="${BACKUP_DIR}/snapshots/${SNAPSHOT_NAME}/layer.tar.gz"
docker save "${COMMIT_IMAGE_NAME}" | gzip > "${LAYER_TAR}"

if [ -f "${LAYER_TAR}" ]; then
    LAYER_SIZE=$(du -h "${LAYER_TAR}" | cut -f1)
    log "Commit layer exported: ${LAYER_TAR} (${LAYER_SIZE})"
else
    error "Failed to export commit layer"
    exit 1
fi

# Step 5: Backup volumes
log "Backing up volumes..."
VOLUMES_BACKUP_NAME="volumes-${TIMESTAMP}"
if bash /opt/backup.sh "${VOLUMES_BACKUP_NAME}"; then
    VOLUMES_TAR="${BACKUP_DIR}/${VOLUMES_BACKUP_NAME}.tar.gz"
    VOLUMES_METADATA="${BACKUP_DIR}/${VOLUMES_BACKUP_NAME}.json"

    if [ -f "${VOLUMES_TAR}" ]; then
        VOLUMES_SIZE=$(du -h "${VOLUMES_TAR}" | cut -f1)
        log "Volumes backed up: ${VOLUMES_TAR} (${VOLUMES_SIZE})"
    else
        warn "Volumes backup file not found"
        VOLUMES_SIZE="unknown"
    fi
else
    error "Failed to backup volumes"
    exit 1
fi

# Step 6: Create metadata
METADATA_FILE="${BACKUP_DIR}/snapshots/${SNAPSHOT_NAME}/metadata.json"
cat > "${METADATA_FILE}" << EOF
{
  "name": "${SNAPSHOT_NAME}",
  "timestamp": "${TIMESTAMP}",
  "created_at": "$(date -Iseconds)",
  "base_image": {
    "id": "${BASE_IMAGE_ID}",
    "short_id": "${BASE_IMAGE_SHORT_ID}",
    "name": "${BASE_IMAGE}",
    "file": "${BASE_IMAGE_FILE}",
    "size": "${BASE_IMAGE_SIZE}"
  },
  "layer": {
    "file": "layer.tar.gz",
    "size": "${LAYER_SIZE}",
    "image_name": "${COMMIT_IMAGE_NAME}"
  },
  "volumes_backup": "${VOLUMES_BACKUP_NAME}",
  "volumes_size": "${VOLUMES_SIZE}",
  "total_size": "Base: ${BASE_IMAGE_SIZE} + Layer: ${LAYER_SIZE} + Volumes: ${VOLUMES_SIZE}"
}
EOF

log "Snapshot metadata saved: ${METADATA_FILE}"

# Step 7: Create symlink to volumes backup
ln -sf "${VOLUMES_TAR}" "${BACKUP_DIR}/snapshots/${SNAPSHOT_NAME}/volumes.tar.gz"
ln -sf "${VOLUMES_METADATA}" "${BACKUP_DIR}/snapshots/${SNAPSHOT_NAME}/volumes-metadata.json"

# Step 8: Clean up old snapshots
log "Cleaning up old snapshots (keeping last ${MAX_SNAPSHOTS})..."
SNAPSHOT_COUNT=$(find "${BACKUP_DIR}/snapshots" -mindepth 1 -maxdepth 1 -type d -name "snapshot-*" | wc -l)

if [ "$SNAPSHOT_COUNT" -gt "$MAX_SNAPSHOTS" ]; then
    find "${BACKUP_DIR}/snapshots" -mindepth 1 -maxdepth 1 -type d -name "snapshot-*" \
        -printf "%T@ %p\n" | \
        sort -n | \
        head -n -$((MAX_SNAPSHOTS)) | \
        cut -d' ' -f2- | \
        while read -r old_snapshot; do
        log "Removing old snapshot: ${old_snapshot}"
        rm -rf "${old_snapshot}"
    done
fi

# Step 9: Clean up old volume backups
log "Cleaning up old volume backups (keeping last ${MAX_SNAPSHOTS})..."
VOLUME_BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/volumes-*.tar.gz 2>/dev/null | wc -l)

if [ "$VOLUME_BACKUP_COUNT" -gt "$MAX_SNAPSHOTS" ]; then
    ls -1t "${BACKUP_DIR}"/volumes-*.tar.gz | tail -n +$((MAX_SNAPSHOTS + 1)) | while read -r old_backup; do
        log "Removing old volume backup: ${old_backup}"
        rm -f "${old_backup}"
        rm -f "${old_backup%.tar.gz}.json"
    done
fi

log "Snapshot created successfully!"
log "Snapshot location: ${BACKUP_DIR}/snapshots/${SNAPSHOT_NAME}"
log "Metadata: ${METADATA_FILE}"
info "Base image: ${BASE_IMAGE_SIZE}"
info "Commit layer: ${LAYER_SIZE}"
info "Volumes: ${VOLUMES_SIZE}"
info "Total storage: ${BASE_IMAGE_SIZE} (base) + ${LAYER_SIZE} (layer) + ${VOLUMES_SIZE} (volumes)"

# List all available snapshots
log "Available snapshots:"
find "${BACKUP_DIR}/snapshots" -mindepth 1 -maxdepth 1 -type d -name "snapshot-*" -printf "%f\n" | sort -r | head -10 || echo "  No snapshots found"
