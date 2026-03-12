#!/bin/bash
#
# WebCode Backup Script
#
# Backs up all Docker volumes to a compressed tarball
# Usage: backup.sh [backup_name]
#   backup_name - optional, defaults to webcode-YYYYMMDD-HHMMSS
#

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/backups}"
BACKUP_NAME="${1:-webcode-$(date +%Y%m%d-%H%M%S)}"
BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
MAX_BACKUPS="${MAX_BACKUPS:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[backup]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[backup]${NC} $1"
}

error() {
    echo -e "${RED}[backup]${NC} $1"
}

# List of volumes to backup (from docker-compose.yml)
VOLUMES=(
    "webcode-docker_dna-data"
    "webcode-docker_projects"
    "webcode-docker_vibe-kanban-data"
    "webcode-docker_code-server-data"
    "webcode-docker_user-data"
    "webcode-docker_openclaw-data"
    "webcode-docker_chrome-data"
    "webcode-docker_v2rayn-data"
    "webcode-docker_gitconfig"
    "webcode-docker_recordings"
    "webcode-docker_webcode-config"
)

# Create backup directory
mkdir -p "$BACKUP_DIR"

log "Starting backup: $BACKUP_NAME"
log "Backup directory: $BACKUP_DIR"

# Check if volumes exist
missing_volumes=()
for vol in "${VOLUMES[@]}"; do
    if ! docker volume inspect "$vol" >/dev/null 2>&1; then
        missing_volumes+=("$vol")
    fi
done

if [ ${#missing_volumes[@]} -gt 0 ]; then
    warn "The following volumes do not exist and will be skipped:"
    for vol in "${missing_volumes[@]}"; do
        warn "  - $vol"
    fi
fi

# Create temporary container for backup
log "Creating temporary backup container..."
TEMP_CONTAINER=$(docker create \
    -v webcode-docker_dna-data:/backup/dna-data \
    -v webcode-docker_projects:/backup/projects \
    -v webcode-docker_vibe-kanban-data:/backup/vibe-kanban-data \
    -v webcode-docker_code-server-data:/backup/code-server-data \
    -v webcode-docker_user-data:/backup/user-data \
    -v webcode-docker_openclaw-data:/backup/openclaw-data \
    -v webcode-docker_chrome-data:/backup/chrome-data \
    -v webcode-docker_v2rayn-data:/backup/v2rayn-data \
    -v webcode-docker_gitconfig:/backup/gitconfig \
    -v webcode-docker_recordings:/backup/recordings \
    -v webcode-docker_webcode-config:/backup/webcode-config \
    -v "$BACKUP_DIR:/output" \
    ubuntu:22.04 \
    tar czf "/output/$(basename "$BACKUP_FILE")" -C /backup .)

# Start the container to create backup
log "Creating backup archive..."
docker start "$TEMP_CONTAINER" >/dev/null 2>&1

# Wait for backup to complete
if docker wait "$TEMP_CONTAINER" >/dev/null 2>&1; then
    log "Backup created successfully: $BACKUP_FILE"

    # Get backup size
    if [ -f "$BACKUP_FILE" ]; then
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        log "Backup size: $BACKUP_SIZE"
    fi
else
    error "Backup creation failed"
    docker rm "$TEMP_CONTAINER" >/dev/null 2>&1
    exit 1
fi

# Clean up temporary container
docker rm "$TEMP_CONTAINER" >/dev/null 2>&1

# Create backup metadata
METADATA_FILE="$BACKUP_DIR/${BACKUP_NAME}.json"
cat > "$METADATA_FILE" << EOF
{
  "name": "$BACKUP_NAME",
  "created_at": "$(date -Iseconds)",
  "size": "$BACKUP_SIZE",
  "volumes": [
    "dna-data",
    "projects",
    "vibe-kanban-data",
    "code-server-data",
    "user-data",
    "openclaw-data",
    "chrome-data",
    "v2rayn-data",
    "gitconfig",
    "recordings",
    "webcode-config"
  ]
}
EOF

log "Backup metadata saved: $METADATA_FILE"

# Clean up old backups (keep only MAX_BACKUPS most recent)
log "Cleaning up old backups (keeping last $MAX_BACKUPS)..."
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/webcode-*.tar.gz 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    ls -1t "$BACKUP_DIR"/webcode-*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | while read -r old_backup; do
        log "Removing old backup: $old_backup"
        rm -f "$old_backup"
        # Also remove metadata file if exists
        rm -f "${old_backup%.tar.gz}.json"
    done
fi

log "Backup completed successfully!"
log "Backup file: $BACKUP_FILE"
log "Metadata: $METADATA_FILE"

# List all available backups
log "Available backups:"
ls -lh "$BACKUP_DIR"/webcode-*.tar.gz 2>/dev/null || echo "  No backups found"
