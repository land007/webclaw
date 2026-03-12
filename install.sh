#!/bin/bash
set -e

#############################################
# webcode One-Command Installer
# https://github.com/land007/webcode
#############################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/land007/webcode"
REPO_URL_MIRROR="https://ghproxy.com/https://github.com/land007/webcode"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/land007/webcode/main/launcher/assets/docker-compose.yml"
DOCKER_COMPOSE_URL_MIRROR="https://ghproxy.com/https://raw.githubusercontent.com/land007/webcode/main/launcher/assets/docker-compose.yml"
INSTALLER_URL="https://raw.githubusercontent.com/land007/webcode/main/install.sh"
INSTALL_DIR="$HOME/webcode"

# Detect if we need sudo for docker
DOCKER_CMD="docker"
IN_CONTAINER=0
[ -f /.dockerenv ] && IN_CONTAINER=1
grep -qa docker /proc/1/cgroup >/dev/null 2>&1 && IN_CONTAINER=1

if [ $IN_CONTAINER -eq 1 ]; then
    # Inside container, always use sudo
    DOCKER_CMD="sudo docker"
elif ! docker info >/dev/null 2>&1; then
    # Try with sudo if regular docker fails
    DOCKER_CMD="sudo docker"
fi

#############################################
# Helper Functions
#############################################

print_logo() {
    cat << "EOF"
   __                    __              __
  / /____  __  _______  / /_____  ____  / /___ _
 / __/ _ \/ / / / ___/ / __/ __ \/ __ \/ / __ `/
/ /_/  __/ /_/ / /    / /_/ /_/ / /_/ / / /_/ /
\__/\___/\__,_/_/     \__/\____/\____/_/\__,_/

One-command browser-based dev environment installer
EOF
    printf "\n"
}

print_header() {
    printf "${CYAN}▸ $1${NC}\n"
}

print_success() {
    printf "${GREEN}✓ $1${NC}\n"
}

print_error() {
    printf "${RED}✗ $1${NC}\n"
}

print_warning() {
    printf "${YELLOW}⚠ $1${NC}\n"
}

print_info() {
    printf "${BLUE}  → $1${NC}\n"
}

detect_os() {
    case "$(uname -s)" in
        Linux*)     OS="linux";;
        Darwin*)    OS="macos";;
        *)          OS="unknown";;
    esac

    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x64";;
        aarch64|arm64) ARCH="arm64";;
        armv7l) ARCH="armv7l";;
        *) ARCH="$ARCH";;
    esac
}

check_docker() {
    if ! type $DOCKER_CMD >/dev/null 2>&1; then
        print_error "Docker is not installed"
        printf "\n"
        print_header "Install Docker:"
        if [ "$OS" = "macos" ]; then
            print_info "Visit: https://www.docker.com/products/docker-desktop"
            print_info "Or use: brew install --cask docker"
        elif [ "$OS" = "linux" ]; then
            print_info "Visit: https://docs.docker.com/engine/install/"
            print_info "Or use: curl -fsSL https://get.docker.com | sh"
        fi
        return 1
    fi

    # Detect if running inside container
    IN_CONTAINER=0
    [ -f /.dockerenv ] && IN_CONTAINER=1
    grep -qa docker /proc/1/cgroup >/dev/null 2>&1 && IN_CONTAINER=1

    # Check if Docker is running (skip strict check in container)
    if [ $IN_CONTAINER -eq 0 ]; then
        # Not in container - require docker info to work
        if ! $DOCKER_CMD info >/dev/null 2>&1; then
            print_error "Docker is not running"
            print_info "Please start Docker and try again."
            return 1
        fi
    else
        # In container - just check socket exists
        if [ ! -S /var/run/docker.sock ]; then
            print_warning "Running inside container without Docker socket"
            print_info "This script should be run on the host machine."
            print_info "Or map Docker socket: -v /var/run/docker.sock:/var/run/docker.sock"
            return 1
        fi
    fi

    # Check for docker compose
    if ! $DOCKER_CMD compose version >/dev/null 2>&1 && ! $DOCKER_CMD-compose version >/dev/null 2>&1; then
        print_error "docker compose is not available"
        print_info "Please install Docker Compose and try again."
        return 1
    fi

    print_success "Docker is installed and running"
    return 0
}

check_git() {
    if ! type git >/dev/null 2>&1; then
        print_error "Git is not installed"
        printf "\n"
        print_header "Install Git:"
        if [ "$OS" = "macos" ]; then
            print_info "Already installed (comes with Xcode Command Line Tools)"
            print_info "If missing: xcode-select --install"
        elif [ "$OS" = "linux" ]; then
            print_info "Ubuntu/Debian: sudo apt install git"
            print_info "Fedora: sudo dnf install git"
            print_info "Arch: sudo pacman -S git"
        fi
        return 1
    fi

    print_success "Git is installed"
    return 0
}

check_nodejs() {
    if ! type node >/dev/null 2>&1; then
        print_warning "Node.js not found (required for Launcher mode)"
        printf "\n"
        print_header "Install Node.js:"
        if [ "$OS" = "macos" ]; then
            print_info "Visit: https://nodejs.org/"
            print_info "Or use: brew install node"
        elif [ "$OS" = "linux" ]; then
            print_info "Visit: https://nodejs.org/"
            print_info "Ubuntu/Debian: curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt install -y nodejs"
            print_info "Fedora: sudo dnf install nodejs"
        fi
        return 1
    fi

    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        print_warning "Node.js $(node -v) found, but 18+ is required for Launcher"
        print_info "Please upgrade Node.js: https://nodejs.org/"
        return 1
    fi

    # Check platform compatibility for Launcher
    if [ "$OS" = "linux" ] && [ "$ARCH" = "arm64" ]; then
        print_warning "Node.js $(node -v) found, but Launcher is not available on Linux ARM64"
        print_info "NW.js does not provide official Linux ARM64 builds."
        print_info "Docker-only mode is fully supported and recommended."
        return 1
    fi

    print_success "Node.js $(node -v) found"
    return 0
}

has_display() {
    [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]
}

# Check all prerequisites
check_prerequisites() {
    local missing_docker=0
    local missing_git=0
    local missing_node=0

    printf "\n"
    print_header "Checking prerequisites..."
    printf "\n"

    # Check Docker (required for all modes)
    if ! check_docker; then
        missing_docker=1
    fi

    # Check Git (required for Launcher mode)
    if ! check_git; then
        missing_git=1
    fi

    # Check Node.js (optional, for Launcher mode)
    check_nodejs || missing_node=1

    printf "\n"

    # Exit if Docker is missing (required)
    if [ $missing_docker -eq 1 ]; then
        print_error "Docker is required for webcode"
        printf "\n"
        print_info "Please install Docker and run this script again."
        exit 1
    fi

    # Return status for Git and Node.js
    return $((missing_git + missing_node))
}

install_docker_mode() {
    print_header "Installing webcode (Docker mode)..."

    # Create install directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Download docker-compose.yml (with mirror fallback)
    print_info "Downloading docker-compose.yml..."
    if curl -fsSL --connect-timeout 10 "$DOCKER_COMPOSE_URL" -o docker-compose.yml 2>/dev/null; then
        print_success "Downloaded docker-compose.yml"
    else
        print_warning "GitHub unreachable, trying mirror..."
        if curl -fsSL --connect-timeout 15 "$DOCKER_COMPOSE_URL_MIRROR" -o docker-compose.yml 2>/dev/null; then
            print_success "Downloaded docker-compose.yml (via mirror)"
        else
            print_error "Failed to download docker-compose.yml"
            print_info "Check your internet connection and try again."
            exit 1
        fi
    fi

    # Ask for custom passwords (optional)
    printf "\n"
    read -rp "$(printf "${YELLOW}Customize credentials? [y/N]: ${NC}")" customize < /dev/tty
    if [ "$customize" = "y" ] || [ "$customize" = "Y" ]; then
        read -rp "Basic Auth username [admin]: " auth_user < /dev/tty
        auth_user=${auth_user:-admin}

        read -rsp "Basic Auth password [changeme]: " auth_password < /dev/tty
        printf "\n"
        auth_password=${auth_password:-changeme}

        read -rsp "VNC password [changeme]: " vnc_password < /dev/tty
        printf "\n"
        vnc_password=${vnc_password:-changeme}

        # Create .env file
        cat > .env << EOF
AUTH_USER=$auth_user
AUTH_PASSWORD=$auth_password
VNC_PASSWORD=$vnc_password
EOF
        print_success "Created .env with custom credentials"
    else
        print_info "Using default credentials (admin/changeme)"
    fi

    # Start container
    printf "\n"
    print_header "Starting container..."
    if $DOCKER_CMD compose up -d; then
        print_success "Container started successfully"
    else
        print_error "Failed to start container"
        exit 1
    fi

    # Wait for services to be ready
    print_info "Waiting for services to start..."
    sleep 5

    print_success "Installation complete!"
}

install_launcher_mode() {
    print_header "Installing webcode (Launcher mode)..."

    # Check for git
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed"
        print_info "Please install Git and try again."
        exit 1
    fi

    # Clone repository
    print_info "Cloning repository..."
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Directory already exists: $INSTALL_DIR"
        read -rp "Remove and re-clone? [y/N]: " remove_clone < /dev/tty
        if [ "$remove_clone" = "y" ] || [ "$remove_clone" = "Y" ]; then
            rm -rf "$INSTALL_DIR"
        else
            print_info "Using existing installation"
            cd "$INSTALL_DIR/launcher"
        fi
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        if git clone "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
            print_success "Repository cloned"
            cd "$INSTALL_DIR/launcher"
        else
            print_warning "GitHub unreachable, trying mirror..."
            if git clone "$REPO_URL_MIRROR" "$INSTALL_DIR"; then
                print_success "Repository cloned (via mirror)"
                cd "$INSTALL_DIR/launcher"
            else
                print_error "Failed to clone repository"
                exit 1
            fi
        fi
    fi

    # Install dependencies
    print_info "Installing dependencies..."
    cd "$INSTALL_DIR/launcher"
    if npm install; then
        print_success "Dependencies installed"
    else
        print_error "Failed to install dependencies"
        exit 1
    fi

    # Ensure nw is installed (for Launcher)
    if [ ! -f "node_modules/.bin/nw" ]; then
        print_info "Installing NW.js..."
        if npm install --save-dev nw; then
            print_success "NW.js installed"
        else
            print_error "Failed to install NW.js"
            exit 1
        fi
    fi

    # Start Launcher
    printf "\n"
    print_success "Installation complete!"
    print_header "Starting Launcher..."
    print_info "A GUI window will appear where you can configure and start webcode."
    printf "\n"
    print_info "To restart later: cd $INSTALL_DIR/launcher && npm start"
    printf "\n"
    exec ./node_modules/.bin/nw .
}

print_completion_info() {
    printf "\n"
    print_header "═══════════════════════════════════════════════════════════════"
    print_success "webcode is ready!"
    print_header "═══════════════════════════════════════════════════════════════"
    printf "\n"
    print_header "Access Points:"
    printf "\n"
    printf "  %-20s %s\n" "Theia IDE"        "http://localhost:20001"
    printf "  %-20s %s\n" "Vibe Kanban"      "http://localhost:20002"
    printf "  %-20s %s\n" "OpenClaw AI"      "http://localhost:20003"
    printf "  %-20s %s\n" "noVNC Desktop"    "http://localhost:20004"
    printf "  %-20s %s\n" "VNC Client"       "localhost:20005"
    printf "\n"
    print_header "Default Credentials:"
    print_info "Basic Auth: ${GREEN}admin${NC} / ${GREEN}changeme${NC}"
    print_info "VNC Password: ${GREEN}changeme${NC}"
    printf "\n"
    print_header "Common Commands:"
    print_info "View status:    cd $INSTALL_DIR && docker compose ps"
    print_info "View logs:      cd $INSTALL_DIR && docker compose logs -f"
    print_info "Stop:           cd $INSTALL_DIR && docker compose down"
    print_info "Restart:        cd $INSTALL_DIR && docker compose restart"
    printf "\n"
    print_header "Documentation:"
    print_info "GitHub:  $REPO_URL"
    print_info "Docker:  https://hub.docker.com/r/land007/webcode"
    printf "\n"
}

#############################################
# Main Flow
#############################################

main() {
    print_logo

    # Detect OS
    detect_os
    print_info "Detected OS: $OS ($ARCH)"

    # Check all prerequisites
    check_prerequisites || true  # Don't exit on Node.js/Git check failure

    # Determine install mode
    printf "\n"

    # Check if Launcher is supported
    LAUNCHER_SUPPORTED=0
    if check_nodejs; then
        LAUNCHER_SUPPORTED=1
    fi

    if has_display || [ "$OS" = "macos" ]; then
        if has_display; then
            print_header "Desktop environment detected"
        else
            print_header "macOS detected (remote session)"
        fi
        printf "\n"
        print_info "Choose installation method:"
        printf "\n"

        if [ $LAUNCHER_SUPPORTED -eq 1 ]; then
            echo -e "  ${GREEN}[1]${NC} Launcher (Recommended)"
            echo -e "      GUI for easy configuration"
            printf "\n"
            echo -e "  ${GREEN}[2]${NC} Docker Only"
            echo -e "      Command-line installation"
            printf "\n"
            read -rp "$(printf "${CYAN}Enter choice [1-2]: ${NC}")" choice < /dev/tty
        else
            echo -e "  ${GREEN}[1]${NC} Docker Only"
            echo -e "      Command-line installation (recommended for this system)"
            printf "\n"
            print_warning "Launcher is not available on this platform"
            print_info "Press Enter to continue with Docker installation..."
            read -r choice < /dev/tty
            choice=2
        fi

        case $choice in
            1)
                printf "\n"
                # Check Node.js again for Launcher mode
                if ! check_nodejs; then
                    print_error "Launcher requires Node.js 18+"
                    printf "\n"
                    print_info "Please install Node.js first, then choose:"
                    printf "\n"
                    echo -e "  ${GREEN}[1]${NC} Exit to install Node.js"
                    echo -e "  ${GREEN}[2]${NC} Use Docker-only mode instead"
                    printf "\n"
                    read -rp "$(printf "${CYAN}Enter choice [1-2]: ${NC}")" node_choice < /dev/tty
                    case $node_choice in
                        1)
                            print_info "Install Node.js from: https://nodejs.org/"
                            exit 0
                            ;;
                        2)
                            install_docker_mode
                            print_completion_info
                            ;;
                        *)
                            print_error "Invalid choice"
                            exit 1
                            ;;
                    esac
                else
                    install_launcher_mode
                fi
                ;;
            2)
                install_docker_mode
                print_completion_info
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    else
        print_header "Server mode detected (no display)"
        install_docker_mode
        print_completion_info
    fi
}

# Run main
main
