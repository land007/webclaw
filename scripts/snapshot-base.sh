#!/bin/bash
#
# WebCode Base Image Management Script
#
# Manages base images for snapshot system:
# - List all base images
# - Export a base image
# - Delete unused base images
# - Show which snapshots use each base image
#
# Usage:
#   snapshot-base.sh list                    - List all base images
#   snapshot-base.sh export <image>          - Export a base image
#   snapshot-base.sh delete <short_id>       - Delete a base image
#   snapshot-base.sh cleanup                 - Delete unused base images
#

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/backups}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[base-image]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[base-image]${NC} $1"
}

error() {
    echo -e "${RED}[base-image]${NC} $1"
}

info() {
    echo -e "${BLUE}[base-image]${NC} $1"
}

header() {
    echo -e "${CYAN}$1${NC}"
}

# Ensure base images directory exists
mkdir -p "${BACKUP_DIR}/base-images"

# Function to list all base images
list_base_images() {
    header "=== Base Images ==="
    echo ""

    if [ ! -d "${BACKUP_DIR}/base-images" ] || [ -z "$(ls -A ${BACKUP_DIR}/base-images 2>/dev/null)" ]; then
        info "No base images found"
        echo ""
        return
    fi

    for base_file in "${BACKUP_DIR}/base-images"/webclaw-base-*.tar.gz; do
        if [ ! -f "$base_file" ]; then
            continue
        fi

        basename_file=$(basename "$base_file")
        short_id=${basename_file#webclaw-base-}
        short_id=${short_id%.tar.gz}

        size=$(du -h "$base_file" | cut -f1)
        modified=$(stat -c %y "$base_file" 2>/dev/null || stat -f "%Sm" "$base_file" 2>/dev/null)
        modified=${modified%%.*}

        # Count snapshots using this base image
        snapshot_count=0
        snapshots_using=()
        for snapshot_dir in "${BACKUP_DIR}/snapshots"/snapshot-*; do
            if [ -d "$snapshot_dir" ] && [ -f "${snapshot_dir}/metadata.json" ]; then
                snapshot_short_id=$(grep -oP '"short_id":\s*"\K[^"]*"' "${snapshot_dir}/metadata.json" 2>/dev/null || echo "")
                if [ "$snapshot_short_id" = "$short_id" ]; then
                    snapshot_count=$((snapshot_count + 1))
                    snapshots_using+=("$(basename "$snapshot_dir")")
                fi
            fi
        done

        echo "📦 ${short_id}"
        echo "   File: ${basename_file}"
        echo "   Size: ${size}"
        echo "   Modified: ${modified}"
        echo "   Used by: ${snapshot_count} snapshot(s)"

        if [ ${#snapshots_using[@]} -gt 0 ]; then
            echo "   Snapshots:"
            for snap in "${snapshots_using[@]}"; do
                echo "     - ${snap}"
            done
        fi

        if [ $snapshot_count -eq 0 ]; then
            echo -e "   ${RED}Status: UNUSED (can be safely deleted)${NC}"
        fi

        echo ""
    done
}

# Function to export a base image
export_base_image() {
    if [ $# -lt 1 ]; then
        error "Usage: $0 export <image_name_or_id>"
        exit 1
    fi

    IMAGE="$1"

    # Check if image exists
    if ! docker inspect "$IMAGE" >/dev/null 2>&1; then
        error "Image not found: ${IMAGE}"
        exit 1
    fi

    # Get image ID
    IMAGE_ID=$(docker inspect "$IMAGE" -f '{{.Id}}')
    SHORT_ID=$(echo "$IMAGE_ID" | cut -d: -f2 | cut -c1-12)
    BASE_IMAGE_FILE="webclaw-base-${SHORT_ID}.tar.gz"
    BASE_IMAGE_PATH="${BACKUP_DIR}/base-images/${BASE_IMAGE_FILE}"

    # Check if already exists
    if [ -f "${BASE_IMAGE_PATH}" ]; then
        warn "Base image already exists: ${BASE_IMAGE_PATH}"
        read -p "Overwrite? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            log "Export cancelled"
            exit 0
        fi
    fi

    log "Exporting base image: ${IMAGE} (${SHORT_ID})"
    docker save "$IMAGE" | gzip > "${BASE_IMAGE_PATH}"

    if [ -f "${BASE_IMAGE_PATH}" ]; then
        SIZE=$(du -h "${BASE_IMAGE_PATH}" | cut -f1)
        log "Base image exported: ${BASE_IMAGE_PATH} (${SIZE})"
    else
        error "Failed to export base image"
        exit 1
    fi
}

# Function to delete a base image
delete_base_image() {
    if [ $# -lt 1 ]; then
        error "Usage: $0 delete <short_id>"
        exit 1
    fi

    SHORT_ID="$1"
    BASE_IMAGE_FILE="webclaw-base-${SHORT_ID}.tar.gz"
    BASE_IMAGE_PATH="${BACKUP_DIR}/base-images/${BASE_IMAGE_FILE}"

    if [ ! -f "${BASE_IMAGE_PATH}" ]; then
        error "Base image not found: ${BASE_IMAGE_PATH}"
        exit 1
    fi

    # Check if any snapshots use this base image
    snapshots_using=()
    for snapshot_dir in "${BACKUP_DIR}/snapshots"/snapshot-*; do
        if [ -d "$snapshot_dir" ] && [ -f "${snapshot_dir}/metadata.json" ]; then
            snapshot_short_id=$(grep -oP '"short_id":\s*"\K[^"]*"' "${snapshot_dir}/metadata.json" 2>/dev/null || echo "")
            if [ "$snapshot_short_id" = "$SHORT_ID" ]; then
                snapshots_using+=("$(basename "$snapshot_dir")")
            fi
        fi
    done

    if [ ${#snapshots_using[@]} -gt 0 ]; then
        error "Cannot delete: ${#snapshots_using[@]} snapshot(s) still using this base image"
        echo ""
        echo "Snapshots using this base image:"
        for snap in "${snapshots_using[@]}"; do
            echo "  - ${snap}"
        done
        echo ""
        echo "Delete these snapshots first, or use --force to delete anyway"
        exit 1
    fi

    # Confirm deletion
    warn "This will delete the base image: ${BASE_IMAGE_PATH}"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log "Deletion cancelled"
        exit 0
    fi

    rm -f "${BASE_IMAGE_PATH}"
    log "Base image deleted: ${BASE_IMAGE_PATH}"
}

# Function to delete unused base images
cleanup_base_images() {
    header "=== Cleaning Up Unused Base Images ==="
    echo ""

    deleted_count=0
    for base_file in "${BACKUP_DIR}/base-images"/webclaw-base-*.tar.gz; do
        if [ ! -f "$base_file" ]; then
            continue
        fi

        basename_file=$(basename "$base_file")
        short_id=${basename_file#webclaw-base-}
        short_id=${short_id%.tar.gz}

        # Check if any snapshots use this base image
        used=false
        for snapshot_dir in "${BACKUP_DIR}/snapshots"/snapshot-*; do
            if [ -d "$snapshot_dir" ] && [ -f "${snapshot_dir}/metadata.json" ]; then
                snapshot_short_id=$(grep -oP '"short_id":\s*"\K[^"]*"' "${snapshot_dir}/metadata.json" 2>/dev/null || echo "")
                if [ "$snapshot_short_id" = "$short_id" ]; then
                    used=true
                    break
                fi
            fi
        done

        if [ "$used" = false ]; then
            log "Deleting unused base image: ${basename_file}"
            rm -f "$base_file"
            deleted_count=$((deleted_count + 1))
        fi
    done

    echo ""
    if [ $deleted_count -eq 0 ]; then
        info "No unused base images found"
    else
        log "Deleted ${deleted_count} unused base image(s)"
    fi
}

# Main command dispatcher
case "${1:-list}" in
    list)
        list_base_images
        ;;
    export)
        export_base_image "$2"
        ;;
    delete)
        if [ "$2" = "--force" ]; then
            SHORT_ID="$3"
            BASE_IMAGE_FILE="webclaw-base-${SHORT_ID}.tar.gz"
            BASE_IMAGE_PATH="${BACKUP_DIR}/base-images/${BASE_IMAGE_FILE}"
            if [ -f "${BASE_IMAGE_PATH}" ]; then
                rm -f "${BASE_IMAGE_PATH}"
                log "Base image deleted (forced): ${BASE_IMAGE_PATH}"
            else
                error "Base image not found: ${BASE_IMAGE_PATH}"
                exit 1
            fi
        else
            delete_base_image "$2"
        fi
        ;;
    cleanup)
        cleanup_base_images
        ;;
    *)
        echo "Usage: $0 {list|export|delete|cleanup}"
        echo ""
        echo "Commands:"
        echo "  list                    - List all base images"
        echo "  export <image>          - Export a base image"
        echo "  delete <short_id>       - Delete a base image (safe, checks usage)"
        echo "  delete --force <id>     - Delete a base image (force, ignore checks)"
        echo "  cleanup                 - Delete all unused base images"
        exit 1
        ;;
esac
