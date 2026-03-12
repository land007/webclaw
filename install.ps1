# webcode One-Command Installer for Windows
# https://github.com/land007/webcode

# Allow scripts (like npm.ps1) to run in this process only
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

$ErrorActionPreference = "Stop"

# Colors
function Get-Color {
    param([string]$Name)
    $colors = @{
        Cyan    = [ConsoleColor]::Cyan
        Green   = [ConsoleColor]::Green
        Yellow  = [ConsoleColor]::Yellow
        Red     = [ConsoleColor]::Red
        Blue    = [ConsoleColor]::Blue
    }
    return $colors[$Name]
}

# Configuration
$RepoUrl = "https://github.com/land007/webcode"
$RepoUrlMirror = "https://ghproxy.com/https://github.com/land007/webcode"
$DockerComposeUrl = "https://raw.githubusercontent.com/land007/webcode/main/launcher/assets/docker-compose.yml"
$DockerComposeUrlMirror = "https://ghproxy.com/https://raw.githubusercontent.com/land007/webcode/main/launcher/assets/docker-compose.yml"
$InstallDir = "$env:USERPROFILE\webcode"

#############################################
# Helper Functions
#############################################

function Print-Logo {
    Write-Host @"
   __                    __              __
  / /____  __  _______  / /_____  ____  / /___ _
 / __/ _ \/ / / / ___/ / __/ __ \/ __ \/ / __ `/
/ /_/  __/ /_/ / /    / /_/ /_/ / /_/ / / /_/ /
\__/\___/\__,_/_/     \__/\____/\____/_/\__,_/

One-command browser-based dev environment installer
"@
    Write-Host ""
}

function Print-Header {
    param([string]$Message)
    Write-Host "▸ $Message" -ForegroundColor Cyan
}

function Print-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Print-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Print-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Print-Info {
    param([string]$Message)
    Write-Host "  → $Message" -ForegroundColor Blue
}

function Test-DockerInstalled {
    try {
        $null = Get-Command docker -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-DockerRunning {
    try {
        $null = docker version 2>&1
        return $true
    } catch {
        return $false
    }
}

function Test-DockerCompose {
    try {
        $null = docker compose version 2>&1
        return $true
    } catch {
        return $false
    }
}

function Test-GitInstalled {
    try {
        $null = Get-Command git -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-NodeInstalled {
    try {
        $null = Get-Command node -ErrorAction Stop
        $version = node -v
        # Remove 'v' prefix and get major version
        $versionNumber = $version.Substring(1)
        $majorVersion = [int]($versionNumber.Split('.')[0])
        return $majorVersion -ge 18
    } catch {
        return $false
    }
}

function Install-NodeJS {
    Print-Header "Installing Node.js..."

    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Print-Error "Administrator privileges required for installation"
        Write-Host ""
        Print-Info "Please restart PowerShell as Administrator and run:"
        Write-Host "  irm https://raw.githubusercontent.com/land007/webcode/main/install.ps1 | iex" -ForegroundColor Cyan
        Write-Host ""
        return $false
    }

    $tempDir = "$env:TEMP\nodejs-install"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # Download Node.js installer
        Write-Host "Downloading Node.js LTS installer..."
        $installerUrl = "https://nodejs.org/dist/v22.22.0/node-v22.22.0-x64.msi"
        $installerPath = "$tempDir\nodejs-installer.msi"

        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 120
        Print-Success "Downloaded Node.js installer"

        # Install silently
        Write-Host "Installing Node.js (this may take 1-2 minutes)..."
        Write-Host "Please wait..." -ForegroundColor Yellow
        $installArgs = @(
            "/i"
            $installerPath
            "/quiet"
            "/norestart"
        )

        # Use WaitForExit with timeout to handle long installations
        $process = Start-Process "msiexec.exe" -ArgumentList $installArgs -PassThru -NoNewWindow

        # Wait up to 5 minutes
        $timeout = 300000  # 5 minutes in milliseconds
        if (!$process.WaitForExit($timeout)) {
            Print-Warning "Installation is taking longer than expected..."
            Print-Info "The installation will continue in the background."
            Print-Info "Please restart PowerShell after 2 minutes and run this script again."
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
            return $false
        }

        if ($process.ExitCode -eq 0) {
            Print-Success "Node.js installed successfully"

            # Refresh PATH for current session
            $nodePath = "$env:ProgramFiles\nodejs"
            if ($env:PATH -notlike "*$nodePath*") {
                $env:PATH = "$nodePath;$env:PATH"
            }

            # Clean up
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
            return $true
        } else {
            Print-Error "Installation failed (exit code: $($process.ExitCode))"
            if ($process.ExitCode -eq 1603) {
                Print-Info "Error 1603: Possible causes:"
                Print-Info "  - Another installation is in progress"
                Print-Info "  - Conflicting version of Node.js already installed"
                Print-Info "  - Insufficient disk space"
                Write-Host ""
                Print-Info "Try uninstalling existing Node.js first:"
                Print-Info "  Settings > Apps > Apps & features > Node.js > Uninstall"
            }
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        Print-Error "Failed to download/install Node.js: $_"
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

        Write-Host ""
        Print-Header "Install Node.js manually:"
        Print-Info "Visit: https://nodejs.org/"
        Print-Info "Download and install the LTS version, then run this script again."
        Write-Host ""
        return $false
    }
}

function Install-DockerMode {
    Print-Header "Installing webcode (Docker mode)..."

    # Create install directory
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    Set-Location $InstallDir

    # Download docker-compose.yml (with mirror fallback)
    Print-Info "Downloading docker-compose.yml..."
    $downloaded = $false
    try {
        Invoke-WebRequest -Uri $DockerComposeUrl -OutFile "docker-compose.yml" -UseBasicParsing -TimeoutSec 10
        Print-Success "Downloaded docker-compose.yml"
        $downloaded = $true
    } catch {
        Print-Warning "GitHub unreachable, trying mirror..."
    }
    if (-not $downloaded) {
        try {
            Invoke-WebRequest -Uri $DockerComposeUrlMirror -OutFile "docker-compose.yml" -UseBasicParsing -TimeoutSec 20
            Print-Success "Downloaded docker-compose.yml (via mirror)"
        } catch {
            Print-Error "Failed to download docker-compose.yml"
            Print-Info "Check your internet connection and try again."
            Read-Host "Press Enter to exit"
            exit 1
        }
    }

    # Ask for custom credentials
    Write-Host ""
    Write-Host "Customize credentials? [y/N]: " -NoNewline -ForegroundColor Yellow
    $customize = Read-Host
    if ($customize -eq 'y' -or $customize -eq 'Y') {
        $authUser = Read-Host "Basic Auth username [admin]"
        if ([string]::IsNullOrWhiteSpace($authUser)) { $authUser = "admin" }

        $authPassword = Read-Host "Basic Auth password [changeme]"
        if ([string]::IsNullOrWhiteSpace($authPassword)) { $authPassword = "changeme" }

        $vncPassword = Read-Host "VNC password [changeme]"
        if ([string]::IsNullOrWhiteSpace($vncPassword)) { $vncPassword = "changeme" }

        # Create .env file
        @"
AUTH_USER=$authUser
AUTH_PASSWORD=$authPassword
VNC_PASSWORD=$vncPassword
"@ | Out-File -FilePath ".env" -Encoding UTF8
        Print-Success "Created .env with custom credentials"
    } else {
        Print-Info "Using default credentials (admin/changeme)"
    }

    # Start container
    Write-Host ""
    Print-Header "Starting container..."
    try {
        docker compose up -d
        Print-Success "Container started successfully"
    } catch {
        Print-Error "Failed to start container"
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Wait for services to be ready
    Print-Info "Waiting for services to start..."
    Start-Sleep -Seconds 5

    Print-Success "Installation complete!"
}

function Install-LauncherMode {
    Print-Header "Installing webcode (Launcher mode)..."

    # Check for git
    if (-not (Test-GitInstalled)) {
        Print-Error "Git is not installed"
        Print-Info "Please install Git: https://git-scm.com/download/win"
        Read-Host "Press Enter to exit"
        exit 1
    }
    Print-Success "Git is available"

    # Clone repository
    Write-Host ""
    Print-Info "Cloning repository from GitHub..."
    Print-Info "This may take a minute depending on your connection..."
    Write-Host ""
    # Check if existing installation is complete (has launcher/package.json)
    $launcherOk = (Test-Path "$InstallDir\launcher\package.json")

    if ((Test-Path $InstallDir) -and $launcherOk) {
        Print-Warning "Directory already exists: $InstallDir"
        Write-Host "Remove and re-clone? [y/N]: " -NoNewline -ForegroundColor Yellow
        $removeClone = Read-Host
        if ($removeClone -eq 'y' -or $removeClone -eq 'Y') {
            Remove-Item -Recurse -Force $InstallDir
        } else {
            Print-Info "Using existing installation"
        }
    } elseif (Test-Path $InstallDir) {
        # Directory exists but incomplete, remove and re-clone
        Print-Warning "Existing directory is incomplete, re-cloning..."
        Remove-Item -Recurse -Force $InstallDir
    }

    if (-not (Test-Path $InstallDir)) {
        $cloned = $false
        # Try GitHub first (2>$null suppresses stderr to avoid NativeCommandError)
        Print-Info "Cloning from GitHub..."
        git clone --quiet $RepoUrl $InstallDir 2>$null
        if ($LASTEXITCODE -eq 0) {
            Print-Success "Repository cloned"
            $cloned = $true
        }
        # Fallback to mirror
        if (-not $cloned) {
            Print-Warning "GitHub unreachable, trying mirror..."
            git clone $RepoUrlMirror $InstallDir
            if ($LASTEXITCODE -eq 0) {
                Print-Success "Repository cloned (via mirror)"
                $cloned = $true
            }
        }
        if (-not $cloned) {
            Print-Error "Failed to clone repository"
            Write-Host ""
            Print-Info "Try cloning manually:"
            Print-Info "  git clone $RepoUrl $InstallDir"
            Print-Info "  cd $InstallDir\launcher"
            Print-Info "  npm install"
            Read-Host "Press Enter to exit"
            exit 1
        }
    }

    # Install dependencies
    Print-Info "Installing dependencies (this may take a minute)..."
    Set-Location "$InstallDir\launcher"
    npm install
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Failed to install dependencies"
        Write-Host ""
        Print-Info "Try running manually:"
        Print-Info "  cd $InstallDir\launcher"
        Print-Info "  npm install"
        Read-Host "Press Enter to exit"
        exit 1
    }
    Print-Success "Dependencies installed"

    # Ensure nw is installed
    if (-not (Test-Path "node_modules\nw")) {
        Print-Info "Installing NW.js..."
        npm install --save-dev nw
        if ($LASTEXITCODE -ne 0) {
            Print-Error "Failed to install NW.js"
            Write-Host ""
            Print-Info "Try running manually:"
            Print-Info "  cd $InstallDir\launcher"
            Print-Info "  npm install --save-dev nw"
            Read-Host "Press Enter to exit"
            exit 1
        }
        Print-Success "NW.js installed"
    }

    # Start Launcher
    Write-Host ""
    Print-Success "Installation complete!"
    Print-Header "Starting Launcher..."
    Print-Info "A GUI window will appear where you can configure and start webcode."
    Write-Host ""
    Print-Info "To restart later: cd $InstallDir\launcher; npm start"
    Write-Host ""
    Print-Info "Press Ctrl+C to stop the Launcher"
    Write-Host ""

    $nwBin = "$InstallDir\launcher\node_modules\.bin\nw.cmd"
    if (-not (Test-Path $nwBin)) {
        $nwBin = "$InstallDir\launcher\node_modules\nw\nwjs\nw.exe"
    }
    try {
        & $nwBin "$InstallDir\launcher"
    } catch {
        Print-Error "Failed to start Launcher"
        Write-Host ""
        Print-Info "Try starting manually:"
        Print-Info "  cd $InstallDir\launcher"
        Print-Info "  .\node_modules\.bin\nw.cmd ."
        Read-Host "Press Enter to exit"
    }
}

function Print-CompletionInfo {
    Write-Host ""
    Print-Header "═══════════════════════════════════════════════════════════════"
    Print-Success "webcode is ready!"
    Print-Header "═══════════════════════════════════════════════════════════════"
    Write-Host ""
    Print-Header "Access Points:"
    Write-Host ""
    Write-Host "  Theia IDE        http://localhost:20001"
    Write-Host "  Vibe Kanban      http://localhost:20002"
    Write-Host "  OpenClaw AI      http://localhost:20003"
    Write-Host "  noVNC Desktop    http://localhost:20004"
    Write-Host "  VNC Client       localhost:20005"
    Write-Host ""
    Print-Header "Default Credentials:"
    Write-Host "  Basic Auth: " -NoNewline
    Write-Host "admin / changeme" -ForegroundColor Green
    Write-Host "  VNC Password: " -NoNewline
    Write-Host "changeme" -ForegroundColor Green
    Write-Host ""
    Print-Header "Common Commands:"
    Print-Info "View status:    cd $InstallDir; docker compose ps"
    Print-Info "View logs:      cd $InstallDir; docker compose logs -f"
    Print-Info "Stop:           cd $InstallDir; docker compose down"
    Print-Info "Restart:        cd $InstallDir; docker compose restart"
    Write-Host ""
    Print-Header "Documentation:"
    Print-Info "GitHub:  $RepoUrl"
    Print-Info "Docker:  https://hub.docker.com/r/land007/webcode"
    Write-Host ""
}

#############################################
# Main Flow
#############################################

function Main {
    Print-Logo

    Print-Info "Detected OS: Windows"

    Write-Host ""
    Print-Header "Checking prerequisites..."
    Write-Host ""

    # Check Docker
    if (-not (Test-DockerInstalled)) {
        Print-Error "Docker is not installed"
        Write-Host ""
        Print-Header "Install Docker Desktop:"
        Print-Info "Visit: https://www.docker.com/products/docker-desktop"
        Write-Host "  Download and install Docker Desktop for Windows, then run this script again."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Print-Success "Docker is installed"

    # Check if Docker is running
    if (-not (Test-DockerRunning)) {
        Print-Error "Docker is not running"
        Print-Info "Please start Docker Desktop and try again."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Print-Success "Docker is running"

    # Check Docker Compose
    if (-not (Test-DockerCompose)) {
        Print-Error "docker compose is not available"
        Print-Info "Please install Docker Compose and try again."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Print-Success "Docker Compose is available"

    # Check Git (for Launcher)
    $gitInstalled = Test-GitInstalled
    if ($gitInstalled) {
        Print-Success "Git is installed"
    }

    # Check Node.js (for Launcher)
    $nodeInstalled = Test-NodeInstalled
    if ($nodeInstalled) {
        $nodeVersion = node -v
        Print-Success "Node.js $nodeVersion found"
    } else {
        $nodeExists = $false
        try {
            $null = Get-Command node -ErrorAction Stop
            $nodeExists = $true
        } catch {}

        if ($nodeExists) {
            $nodeVersion = node -v
            Print-Warning "Node.js $nodeVersion found, but 18+ is required for Launcher"
        } else {
            Print-Warning "Node.js not found (required for Launcher mode)"
        }

        Write-Host ""
        Write-Host "Install Node.js now? [y/N]: " -NoNewline -ForegroundColor Yellow
        $installNode = Read-Host

        if ($installNode -eq 'y' -or $installNode -eq 'Y') {
            Write-Host ""
            if (Install-NodeJS) {
                # Verify installation
                $nodeInstalled = Test-NodeInstalled
                if ($nodeInstalled) {
                    Print-Success "Node.js $(node -v) is now available"
                } else {
                    Print-Error "Node.js installation verification failed"
                    Write-Host "Please restart your terminal and run this script again."
                    Read-Host "Press Enter to exit"
                    exit 1
                }
            } else {
                # Auto-install failed, ask user what to do
                Write-Host ""
                Write-Host "Continue with Docker-only mode? [Y/n]: " -NoNewline -ForegroundColor Cyan
                $continueDocker = Read-Host
                if ($continueDocker -eq 'n' -or $continueDocker -eq 'N') {
                    exit 0
                }
            }
        }
    }

    Write-Host ""
    Print-Info "Choose installation method:"
    Write-Host ""

    $launcherAvailable = $gitInstalled -and $nodeInstalled
    if ($launcherAvailable) {
        Write-Host "  [1] Launcher (Recommended)"
        Write-Host "      GUI for easy configuration"
        Write-Host ""
        Write-Host "  [2] Docker Only"
        Write-Host "      Command-line installation"
        Write-Host ""

        Write-Host "Enter choice [1-2]: " -NoNewline -ForegroundColor Cyan
        $choice = Read-Host

        switch ($choice) {
            "1" {
                Install-LauncherMode
            }
            "2" {
                Install-DockerMode
                Print-CompletionInfo
            }
            default {
                Print-Info "Using Docker-only mode..."
                Install-DockerMode
                Print-CompletionInfo
            }
        }
    } else {
        Write-Host "  [1] Docker Only"
        Write-Host "      Command-line installation (recommended for this system)"
        Write-Host ""
        Print-Warning "Launcher is not available (requires Git and Node.js 18+)"
        Write-Host "Press Enter to continue with Docker installation..."
        $null = Read-Host

        Install-DockerMode
        Print-CompletionInfo
    }
}

# Run main
Main
