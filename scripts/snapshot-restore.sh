#!/bin/bash
#
# WebCode Snapshot Restore Script (Layered Restore)
#
# Restores a complete snapshot from layered backup:
# 1. Load base image (if not already loaded)
# 2. Load commit layer (Docker automatically merges with base)
# 3. Restore volumes
# 4. Recreate container from snapshot image
#
# Usage: snapshot-restore.sh <snapshot_name> [--force]
#   snapshot_name - name of the snapshot (e.g., snapshot-20260308-143022)
#   --force       - skip confirmation prompt
#

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/backups}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[restore]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[restore]${NC} $1"
}

error() {
    echo -e "${RED}[restore]${NC} $1"
}

info() {
    echo -e "${BLUE}[restore]${NC} $1"
}

# Check arguments
if [ $# -lt 1 ]; then
    error "Usage: $0 <snapshot_name> [--force]"
    echo ""
    info "Available snapshots:"
    find "${BACKUP_DIR}/snapshots" -mindepth 1 -maxdepth 1 -type d -name "snapshot-*" -printf "%f\n" | sort -r || echo "  No snapshots found"
    exit 1
fi

SNAPSHOT_NAME="$1"
SNAPSHOT_DIR="${BACKUP_DIR}/snapshots/${SNAPSHOT_NAME}"
METADATA_FILE="${SNAPSHOT_DIR}/metadata.json"
LAYER_TAR="${SNAPSHOT_DIR}/layer.tar.gz"
FORCE=false

if [ "$2" = "--force" ]; then
    FORCE=true
fi

# Check if snapshot exists
if [ ! -d "${SNAPSHOT_DIR}" ]; then
    error "Snapshot not found: ${SNAPSHOT_DIR}"
    echo ""
    info "Available snapshots:"
    find "${BACKUP_DIR}/snapshots" -mindepth 1 -maxdepth 1 -type d -name "snapshot-*" -printf "%f\n" | sort -r || echo "  No snapshots found"
    exit 1
fi

# Check if metadata exists
if [ ! -f "${METADATA_FILE}" ]; then
    error "Metadata file not found: ${METADATA_FILE}"
    exit 1
fi

# Check if layer tar exists
if [ ! -f "${LAYER_TAR}" ]; then
    error "Snapshot layer not found: ${LAYER_TAR}"
    exit 1
fi

# Parse metadata
BASE_IMAGE_SHORT_ID=$(grep -oP '"short_id":\s*"\K[^"]*"' "$METADATA_FILE")
BASE_IMAGE_FILE=$(grep -oP '"file":\s*"\K[^"]*"' "$METADATA_FILE")
COMMIT_IMAGE_NAME=$(grep -oP '"image_name":\s*"\K[^"]*"' "$METADATA_FILE")
VOLUMES_BACKUP=$(grep -oP '"volumes_backup":\s*"\K[^"]*"' "$METADATA_FILE")

BASE_IMAGE_PATH="${BACKUP_DIR}/base-images/${BASE_IMAGE_FILE}"

# Display snapshot info
log "Snapshot information:"
cat "$METADATA_FILE" | grep -E '(name|created_at|base_image|layer|volumes)' | sed 's/^/  /'
echo ""

# Check if base image exists
if [ ! -f "${BASE_IMAGE_PATH}" ]; then
    error "Base image backup not found: ${BASE_IMAGE_PATH}"
    error "Cannot restore snapshot without base image"
    exit 1
fi

# Confirmation prompt
if [ "$FORCE" != true ]; then
    warn "This will REPLACE all current data with the snapshot!"
    warn "All changes since the snapshot will be LOST!"
    warn "The container will be STOPPED and RECREATED!"
    echo ""
    read -p "Are you sure you want to restore? Type 'yes' to confirm: " confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Restore cancelled"
        exit 0
    fi
fi

log "Starting restore: ${SNAPSHOT_NAME}"

# Step 1: Load base image
log "Loading base image: ${BASE_IMAGE_FILE}"
if ! docker load -i "${BASE_IMAGE_PATH}" 2>/dev/null; then
    # Try with gunzip if direct load fails
    gunzip -c "${BASE_IMAGE_PATH}" | docker load 2>/dev/null || {
        error "Failed to load base image"
        exit 1
    }
fi
log "Base image loaded successfully"

# Step 2: Load commit layer (Docker automatically merges with base)
log "Loading snapshot layer: ${LAYER_TAR}"
if ! docker load -i "${LAYER_TAR}" 2>/dev/null; then
    # Try with gunzip if direct load fails
    gunzip -c "${LAYER_TAR}" | docker load 2>/dev/null || {
        error "Failed to load snapshot layer"
        exit 1
    }
fi
log "Snapshot layer loaded successfully"

# Step 3: Verify snapshot image exists
if ! docker inspect "${COMMIT_IMAGE_NAME}" >/dev/null 2>&1; then
    error "Snapshot image not found after load: ${COMMIT_IMAGE_NAME}"
    exit 1
fi
log "Snapshot image verified: ${COMMIT_IMAGE_NAME}"

# Step 4: Stop services to prevent data corruption
log "Stopping services..."
supervisorctl stop code-server >/dev/null 2>&1 || true
supervisorctl stop vibe-kanban >/dev/null 2>&1 || true
supervisorctl stop openclaw >/dev/null 2>&1 || true
supervisorctl stop claudecodeui >/dev/null 2>&1 || true

# Step 5: Stop and remove current container
log "Stopping current container..."
cd /home/ubuntu/dna 2>/dev/null || cd /home/ubuntu
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    docker-compose down 2>/dev/null || docker compose down 2>/dev/null || true
else
    docker stop webcode 2>/dev/null || true
    docker rm webcode 2>/dev/null || true
fi

# Step 6: Modify docker-compose.yml to use snapshot image
log "Configuring container to use snapshot image..."
cd /home/ubuntu/dna 2>/dev/null || cd /home/ubuntu

if [ -f "docker-compose.yml" ]; then
    # Backup original docker-compose.yml
    cp docker-compose.yml docker-compose.yml.backup

    # Replace image with snapshot image
    if sed -i.tmp 's|image: land007/webcode:.*|image: '"${COMMIT_IMAGE_NAME}"'|g' docker-compose.yml; then
        rm -f docker-compose.yml.tmp
        log "Docker Compose updated to use snapshot image"
    else
        # For macOS sed (no -i)
        sed 's|image: land007/webcode:.*|image: '"${COMMIT_IMAGE_NAME}"'|g' docker-compose.yml > docker-compose.yml.tmp
        mv docker-compose.yml.tmp docker-compose.yml
        log "Docker Compose updated to use snapshot image"
    fi
fi

# Step 7: Start container with snapshot image
log "Starting container with snapshot image..."
if [ -f "docker-compose.yml" ]; then
    if docker-compose up -d 2>/dev/null || docker compose up -d; then
        log "Container started successfully"
    else
        error "Failed to start container"
        # Restore original docker-compose.yml
        if [ -f "docker-compose.yml.backup" ]; then
            mv docker-compose.yml.backup docker-compose.yml
        fi
        exit 1
    fi
else
    error "docker-compose.yml not found"
    exit 1
fi

# Step 8: Restore volumes
log "Restoring volumes..."
if bash /opt/restore.sh "${VOLUMES_BACKUP}" --force; then
    log "Volumes restored successfully"
else
    error "Failed to restore volumes"
    # Restore original docker-compose.yml
    if [ -f "docker-compose.yml.backup" ]; then
        mv docker-compose.yml.backup docker-compose.yml
        docker-compose up -d 2>/dev/null || docker compose up -d
    fi
    exit 1
fi

# Step 9: Restore original docker-compose.yml
log "Restoring original docker-compose.yml..."
if [ -f "docker-compose.yml.backup" ]; then
    mv docker-compose.yml.backup docker-compose.yml
    log "Original docker-compose.yml restored"
fi

# Step 10: Restart services
log "Restarting services..."
supervisorctl start code-server >/dev/null 2>&1 || true
supervisorctl start vibe-kanban >/dev/null 2>&1 || true
supervisorctl start openclaw >/dev/null 2>&1 || true
supervisorctl start claudecodeui >/dev/null 2>&1 || true

log "Snapshot restored successfully!"
log "Snapshot: ${SNAPSHOT_NAME}"
log "Container is now running with snapshot data"
info "Note: The container is using the original docker-compose.yml configuration"
info "      Future restarts will use the standard land007/webcode:latest image"

# Display restore summary
info "Restore summary:"
echo "  Snapshot: ${SNAPSHOT_NAME}"
echo "  Restored at: $(date -Iseconds)"
echo "  Base image: ${BASE_IMAGE_FILE}"
echo "  Commit layer: ${COMMIT_IMAGE_NAME}"
echo "  Volumes: ${VOLUMES_BACKUP}"
