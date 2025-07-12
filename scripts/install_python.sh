#!/bin/bash

# ==============================================================================
# Ubuntu 24.04 Automated Installation Script
# Installs: Python (latest/LTS), pip, uv/uvx, and PowerShell (latest)
# Author: Assistant
# Date: $(date +%Y-%m-%d)
# License: MIT
# ==============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Global variables
SCRIPT_NAME="Ubuntu 24.04 Installer"
LOG_FILE="/tmp/ubuntu_install_$(date +%Y%m%d_%H%M%S).log"
PYTHON_VERSION_PREFERENCE="${PYTHON_VERSION_PREFERENCE:-latest}"  # Can be 'latest' or 'lts'

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons"
        print_error "Please run as a regular user with sudo privileges"
        exit 1
    fi
}

check_ubuntu_version() {
    if ! grep -q "Ubuntu 24.04" /etc/os-release; then
        print_warning "This script is designed for Ubuntu 24.04"
        print_warning "Current OS: $(lsb_release -d | cut -f2)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_internet() {
    print_status "Checking internet connectivity..."
    if ! ping -c 1 google.com &> /dev/null; then
        print_error "No internet connection. Please check your network and try again."
        exit 1
    fi
    print_success "Internet connectivity confirmed"
}

# ==============================================================================
# System Update Functions
# ==============================================================================

update_system() {
    print_status "Updating system packages..."
    
    # Set non-interactive frontend to avoid prompts
    export DEBIAN_FRONTEND=noninteractive
    
    # Update package lists
    sudo apt-get update -y || {
        print_error "Failed to update package lists"
        exit 1
    }
    
    # Upgrade existing packages
    sudo apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || {
        print_error "Failed to upgrade packages"
        exit 1
    }
    
    # Install essential packages
    sudo apt-get install -y \
        curl \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        build-essential \
        git \
        unzip || {
        print_error "Failed to install essential packages"
        exit 1
    }
    
    print_success "System updated successfully"
}

# ==============================================================================
# Python Installation Functions
# ==============================================================================

get_latest_python_version() {
    print_status "Determining latest Python version..."
    
    # Get latest Python 3 version from deadsnakes PPA info
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/python/cpython/releases/latest" | \
        grep -oP '"tag_name": "v\K[0-9]+\.[0-9]+' | head -1)
    
    if [[ -z "$latest_version" ]]; then
        # Fallback to a known recent version
        latest_version="3.12"
        print_warning "Could not determine latest Python version, using fallback: $latest_version"
    fi
    
    echo "$latest_version"
}

get_lts_python_version() {
    # Python 3.12 is the current LTS-like stable version for Ubuntu 24.04
    # This aligns with what Ubuntu 24.04 ships with
    echo "3.12"
}

install_python() {
    print_status "Installing Python..."
    
    local python_version
    if [[ "$PYTHON_VERSION_PREFERENCE" == "lts" ]]; then
        python_version=$(get_lts_python_version)
        print_status "Installing Python LTS version: $python_version"
    else
        python_version=$(get_latest_python_version)
        print_status "Installing latest Python version: $python_version"
    fi
    
    # Check if Python is already installed and what version
    if command -v python3 &> /dev/null; then
        local current_version
        current_version=$(python3 --version | grep -oP '\d+\.\d+')
        print_status "Current Python version: $current_version"
        
        # If we already have the desired version or newer, skip installation
        if dpkg --compare-versions "$current_version" ge "$python_version"; then
            print_success "Python $current_version is already installed and meets requirements"
            return 0
        fi
    fi
    
    # Install Python from Ubuntu repositories first (usually 3.12 for Ubuntu 24.04)
    sudo apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-setuptools \
        python3-wheel || {
        print_error "Failed to install Python from Ubuntu repositories"
        exit 1
    }
    
    # If we need a newer version, add deadsnakes PPA
    if [[ "$PYTHON_VERSION_PREFERENCE" == "latest" ]]; then
        local ubuntu_python_version
        ubuntu_python_version=$(python3 --version | grep -oP '\d+\.\d+')
        
        if dpkg --compare-versions "$ubuntu_python_version" lt "$python_version"; then
            print_status "Adding deadsnakes PPA for newer Python version..."
            
            # Add deadsnakes PPA
            sudo add-apt-repository -y ppa:deadsnakes/ppa || {
                print_warning "Failed to add deadsnakes PPA, continuing with system Python"
                return 0
            }
            
            sudo apt-get update -y
            
            # Install the specific Python version
            sudo apt-get install -y \
                "python${python_version}" \
                "python${python_version}-pip" \
                "python${python_version}-venv" \
                "python${python_version}-dev" || {
                print_warning "Failed to install Python $python_version from deadsnakes, using system Python"
                return 0
            }
            
            # Create symlinks for the newer version
            sudo update-alternatives --install /usr/bin/python3 python3 "/usr/bin/python${python_version}" 1
            print_success "Python $python_version installed from deadsnakes PPA"
        fi
    fi
    
    # Verify Python installation
    local installed_version
    installed_version=$(python3 --version)
    print_success "Python installed: $installed_version"
    
    # Ensure pip is up to date
    python3 -m pip install --user --upgrade pip || {
        print_warning "Failed to upgrade pip, continuing..."
    }
    
    print_success "Python installation completed"
}

# ==============================================================================
# UV/UVX Installation Functions
# ==============================================================================

install_uv() {
    print_status "Installing uv (Python package manager) and uvx..."
    
    # Check if uv is already installed
    if command -v uv &> /dev/null; then
        local current_version
        current_version=$(uv --version | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        print_status "uv is already installed (version: $current_version)"
        
        # Try to update uv
        print_status "Attempting to update uv to latest version..."
        if command -v uv &> /dev/null; then
            uv self update || print_warning "Could not update uv, continuing with current version"
        fi
    else
        # Install uv using the official installer script
        print_status "Downloading and installing uv..."
        
        # Download and run the installer
        curl -LsSf https://astral.sh/uv/install.sh | sh || {
            print_error "Failed to install uv using official installer"
            exit 1
        }
        
        # Add uv to PATH for current session
        export PATH="$HOME/.local/bin:$PATH"
        
        # Add to shell profile for persistence
        local shell_profile
        if [[ -n "${BASH_VERSION:-}" ]]; then
            shell_profile="$HOME/.bashrc"
        elif [[ -n "${ZSH_VERSION:-}" ]]; then
            shell_profile="$HOME/.zshrc"
        else
            shell_profile="$HOME/.profile"
        fi
        
        if [[ -f "$shell_profile" ]] && ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$shell_profile"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_profile"
            print_status "Added uv to PATH in $shell_profile"
        fi
    fi
    
    # Verify installation
    if command -v uv &> /dev/null; then
        local uv_version
        uv_version=$(uv --version)
        print_success "uv installed: $uv_version"
        
        # uvx is part of uv, verify it's available
        if command -v uvx &> /dev/null; then
            print_success "uvx is available (part of uv installation)"
        else
            # uvx might be an alias, check if uv tool run works
            if uv tool --help &> /dev/null; then
                print_success "uvx functionality available via 'uv tool run'"
            else
                print_warning "uvx functionality may not be available"
            fi
        fi
    else
        print_error "uv installation failed"
        exit 1
    fi
    
    print_success "uv/uvx installation completed"
}

# ==============================================================================
# PowerShell Installation Functions
# ==============================================================================

get_latest_powershell_version() {
    print_status "Determining latest PowerShell version..."
    
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" | \
        grep -oP '"tag_name": "v\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    if [[ -z "$latest_version" ]]; then
        print_error "Could not determine latest PowerShell version"
        exit 1
    fi
    
    echo "$latest_version"
}

install_powershell() {
    print_status "Installing PowerShell..."
    
    # Check if PowerShell is already installed
    if command -v pwsh &> /dev/null; then
        local current_version
        current_version=$(pwsh --version | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        print_status "PowerShell is already installed (version: $current_version)"
        
        local latest_version
        latest_version=$(get_latest_powershell_version)
        
        if [[ "$current_version" == "$latest_version" ]]; then
            print_success "PowerShell is already up to date"
            return 0
        else
            print_status "Updating PowerShell from $current_version to $latest_version"
        fi
    fi
    
    # Get the latest PowerShell version
    local ps_version
    ps_version=$(get_latest_powershell_version)
    print_status "Installing PowerShell version: $ps_version"
    
    # Determine architecture
    local arch
    arch=$(dpkg --print-architecture)
    
    # Map architecture to PowerShell naming convention
    local ps_arch
    case "$arch" in
        amd64) ps_arch="x64" ;;
        arm64) ps_arch="arm64" ;;
        armhf) ps_arch="arm32" ;;
        *) 
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Download PowerShell package
    local package_name="powershell_${ps_version}-1.deb_${ps_arch}.deb"
    local download_url="https://github.com/PowerShell/PowerShell/releases/download/v${ps_version}/${package_name}"
    
    print_status "Downloading PowerShell package..."
    wget -q "$download_url" || {
        print_error "Failed to download PowerShell package from $download_url"
        cd - > /dev/null
        rm -rf "$temp_dir"
        exit 1
    }
    
    # Install PowerShell package
    print_status "Installing PowerShell package..."
    sudo dpkg -i "$package_name" || {
        print_status "Resolving dependencies..."
        sudo apt-get install -f -y || {
            print_error "Failed to resolve PowerShell dependencies"
            cd - > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
    }
    
    # Clean up
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    # Verify PowerShell installation
    if command -v pwsh &> /dev/null; then
        local installed_version
        installed_version=$(pwsh --version)
        print_success "PowerShell installed: $installed_version"
    else
        print_error "PowerShell installation verification failed"
        exit 1
    fi
    
    print_success "PowerShell installation completed"
}

# ==============================================================================
# Verification Functions
# ==============================================================================

verify_installations() {
    print_status "Verifying all installations..."
    
    local success=true
    
    # Verify Python
    if command -v python3 &> /dev/null; then
        local python_ver
        python_ver=$(python3 --version)
        print_success "✓ Python: $python_ver"
    else
        print_error "✗ Python: Not found"
        success=false
    fi
    
    # Verify pip
    if command -v pip3 &> /dev/null || python3 -m pip --version &> /dev/null; then
        local pip_ver
        pip_ver=$(python3 -m pip --version | head -1)
        print_success "✓ pip: $pip_ver"
    else
        print_error "✗ pip: Not found"
        success=false
    fi
    
    # Verify uv
    if command -v uv &> /dev/null; then
        local uv_ver
        uv_ver=$(uv --version)
        print_success "✓ uv: $uv_ver"
    else
        print_error "✗ uv: Not found"
        success=false
    fi
    
    # Verify uvx (which is part of uv)
    if command -v uvx &> /dev/null || uv tool --help &> /dev/null; then
        print_success "✓ uvx: Available (via uv tool run)"
    else
        print_error "✗ uvx: Not found"
        success=false
    fi
    
    # Verify PowerShell
    if command -v pwsh &> /dev/null; then
        local ps_ver
        ps_ver=$(pwsh --version)
        print_success "✓ PowerShell: $ps_ver"
    else
        print_error "✗ PowerShell: Not found"
        success=false
    fi
    
    if [[ "$success" == "true" ]]; then
        print_success "All installations verified successfully!"
        return 0
    else
        print_error "Some installations failed verification"
        return 1
    fi
}

display_usage_info() {
    print_status "Installation complete! Here's how to use your new tools:"
    echo
    echo -e "${GREEN}Python:${NC}"
    echo "  python3 --version    # Check Python version"
    echo "  python3 -m pip install package_name    # Install Python packages"
    echo
    echo -e "${GREEN}uv (Ultra-fast Python package manager):${NC}"
    echo "  uv --help           # Show uv help"
    echo "  uv pip install package_name    # Install packages (faster than pip)"
    echo "  uv venv myenv       # Create virtual environment"
    echo
    echo -e "${GREEN}uvx (Run Python tools):${NC}"
    echo "  uvx cowsay 'Hello World!'    # Run tools without installing"
    echo "  uv tool install ruff         # Install tools globally"
    echo
    echo -e "${GREEN}PowerShell:${NC}"
    echo "  pwsh                # Start PowerShell"
    echo "  pwsh -c 'Get-Process'    # Run PowerShell command"
    echo
    echo -e "${YELLOW}Note:${NC} You may need to restart your terminal or run 'source ~/.bashrc' to update your PATH"
}

# ==============================================================================
# Main Installation Flow
# ==============================================================================

main() {
    echo "================================================================================"
    echo "  $SCRIPT_NAME"
    echo "  Installing: Python, pip, uv/uvx, and PowerShell on Ubuntu 24.04"
    echo "  Log file: $LOG_FILE"
    echo "================================================================================"
    echo
    
    # Pre-installation checks
    check_root
    check_ubuntu_version
    check_internet
    
    # System preparation
    update_system
    
    # Install components
    install_python
    install_uv
    install_powershell
    
    # Verify everything worked
    verify_installations || {
        print_error "Installation completed with errors. Check the log file: $LOG_FILE"
        exit 1
    }
    
    # Display usage information
    display_usage_info
    
    print_success "Installation completed successfully!"
    print_status "Log file saved at: $LOG_FILE"
}

# ==============================================================================
# Script Entry Point
# ==============================================================================

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --python-lts        Install Python LTS version instead of latest"
        echo
        echo "Environment variables:"
        echo "  PYTHON_VERSION_PREFERENCE   Set to 'lts' for LTS version, 'latest' for newest (default: latest)"
        echo
        exit 0
        ;;
    --python-lts)
        export PYTHON_VERSION_PREFERENCE="lts"
        shift
        ;;
esac

# Run main installation
main "$@"
