#!/bin/bash

# PowerShell Installation Script for Ubuntu 24.04
# This script automatically installs the latest PowerShell version with oh-my-posh, Terminal-Icons, and other dependencies
# All operations are non-interactive and forced for automated deployment

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
INSTALL_LTS=${INSTALL_LTS:-false}  # Set to true to install LTS version instead of latest stable
FORCE_REINSTALL=${FORCE_REINSTALL:-false}  # Set to true to force reinstall even if already installed
NERD_FONT_NAME="MesloLGM"  # Nerd Font to install for oh-my-posh

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Check Ubuntu version
check_ubuntu_version() {
    if ! grep -q "Ubuntu 24.04" /etc/os-release; then
        log_warning "This script is designed for Ubuntu 24.04. Your system may not be fully supported."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    sudo apt-get update -y &>/dev/null
    sudo apt-get upgrade -y &>/dev/null
    log_success "System packages updated"
}

# Install prerequisites
install_prerequisites() {
    log_info "Installing prerequisites..."
    sudo apt-get install -y \
        wget \
        curl \
        apt-transport-https \
        software-properties-common \
        gpg \
        ca-certificates \
        unzip \
        fontconfig &>/dev/null
    log_success "Prerequisites installed"
}

# Get latest PowerShell version from GitHub API
get_latest_powershell_version() {
    local version_type="$1"  # "stable" or "lts"
    local api_url="https://api.github.com/repos/PowerShell/PowerShell/releases"
    
    if [[ "$version_type" == "lts" ]]; then
        # Get latest LTS version (7.4.x series)
        version=$(curl -s "$api_url" | grep -E '"tag_name":\s*"v7\.4\.' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
    else
        # Get latest stable version
        version=$(curl -s "$api_url/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    fi
    
    if [[ -z "$version" ]]; then
        log_error "Failed to get PowerShell version from GitHub API"
        exit 1
    fi
    
    echo "$version"
}

# Install PowerShell
install_powershell() {
    log_info "Checking for existing PowerShell installation..."
    
    if command -v pwsh &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
        local current_version=$(pwsh -c '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || echo "unknown")
        log_warning "PowerShell is already installed (version: $current_version)"
        log_info "Use FORCE_REINSTALL=true to reinstall"
        return 0
    fi
    
    log_info "Determining PowerShell version to install..."
    local version_type="stable"
    if [[ "$INSTALL_LTS" == "true" ]]; then
        version_type="lts"
        log_info "Installing LTS version..."
    else
        log_info "Installing latest stable version..."
    fi
    
    local ps_version=$(get_latest_powershell_version "$version_type")
    log_info "Latest PowerShell version: $ps_version"
    
    # Construct download URL
    local package_name
    if [[ "$version_type" == "lts" ]]; then
        package_name="powershell-lts_${ps_version}-1.deb_amd64.deb"
    else
        package_name="powershell_${ps_version}-1.deb_amd64.deb"
    fi
    
    local download_url="https://github.com/PowerShell/PowerShell/releases/download/v${ps_version}/${package_name}"
    local temp_file="/tmp/${package_name}"
    
    log_info "Downloading PowerShell $ps_version..."
    if ! wget -q "$download_url" -O "$temp_file"; then
        log_error "Failed to download PowerShell package"
        exit 1
    fi
    
    log_info "Installing PowerShell package..."
    sudo dpkg -i "$temp_file" 2>/dev/null || {
        log_info "Resolving dependencies..."
        sudo apt-get install -f -y &>/dev/null
    }
    
    # Cleanup
    rm -f "$temp_file"
    
    # Verify installation
    if command -v pwsh &>/dev/null; then
        local installed_version=$(pwsh -c '$PSVersionTable.PSVersion.ToString()' 2>/dev/null)
        log_success "PowerShell $installed_version installed successfully"
    else
        log_error "PowerShell installation failed"
        exit 1
    fi
}

# Install Nerd Font for oh-my-posh
install_nerd_font() {
    log_info "Installing Nerd Font ($NERD_FONT_NAME)..."
    
    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"
    
    # Download and install MesloLGM Nerd Font
    local font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${NERD_FONT_NAME}.zip"
    local temp_font_file="/tmp/${NERD_FONT_NAME}.zip"
    
    if wget -q "$font_url" -O "$temp_font_file"; then
        unzip -o -q "$temp_font_file" -d "$font_dir" "*.ttf" 2>/dev/null || true
        rm -f "$temp_font_file"
        
        # Update font cache
        fc-cache -f "$font_dir" &>/dev/null
        log_success "Nerd Font installed"
    else
        log_warning "Failed to download Nerd Font. oh-my-posh may not display icons correctly."
    fi
}

# Install oh-my-posh
install_oh_my_posh() {
    log_info "Installing oh-my-posh..."
    
    # Install oh-my-posh binary
    local install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"
    
    # Download and install oh-my-posh
    if curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$install_dir" &>/dev/null; then
        log_success "oh-my-posh installed"
        
        # Add to PATH if not already there
        if [[ ":$PATH:" != *":$install_dir:"* ]]; then
            echo "export PATH=\"$install_dir:\$PATH\"" >> "$HOME/.bashrc"
            export PATH="$install_dir:$PATH"
        fi
        
        # Create oh-my-posh themes directory
        local themes_dir="$HOME/.oh-my-posh"
        mkdir -p "$themes_dir"
        
        # Download themes
        log_info "Downloading oh-my-posh themes..."
        local themes_url="https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip"
        local temp_themes="/tmp/oh-my-posh-themes.zip"
        
        if wget -q "$themes_url" -O "$temp_themes"; then
            unzip -o -q "$temp_themes" -d "$themes_dir" &>/dev/null
            rm -f "$temp_themes"
            chmod 644 "$themes_dir"/*.omp.json 2>/dev/null || true
            log_success "oh-my-posh themes downloaded"
        else
            log_warning "Failed to download oh-my-posh themes"
        fi
    else
        log_error "Failed to install oh-my-posh"
        exit 1
    fi
}

# Configure PowerShell modules and profile
configure_powershell() {
    log_info "Configuring PowerShell modules and profile..."
    
    # Create PowerShell profile directory
    local ps_profile_dir="$HOME/.config/powershell"
    mkdir -p "$ps_profile_dir"
    
    # Install required PowerShell modules
    log_info "Installing PowerShell modules..."
    pwsh -NonInteractive -Command "
        # Set execution policy for current user
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        
        # Install required modules
        Install-Module -Name Terminal-Icons -Repository PSGallery -Force -Scope CurrentUser
        Install-Module -Name PSReadLine -Repository PSGallery -Force -Scope CurrentUser
        
        Write-Host 'PowerShell modules installed successfully'
    " 2>/dev/null || {
        log_error "Failed to install PowerShell modules"
        exit 1
    }
    
    # Create PowerShell profile with user's configuration
    local profile_path="$ps_profile_dir/Microsoft.PowerShell_profile.ps1"
    
    cat > "$profile_path" << 'EOF'
# PowerShell Profile Configuration
# Auto-generated by PowerShell installation script

# Initialize oh-my-posh with negligible theme
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh --init --shell pwsh --config ~/.oh-my-posh/negligible.omp.json | Invoke-Expression
}

# Import Terminal-Icons module
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module -Name Terminal-Icons
}

# Configure PSReadLine options
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView -ErrorAction SilentlyContinue
}

# Set console encoding to UTF-8
[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

EOF
    
    log_success "PowerShell profile configured"
    
    # Make sure negligible theme exists, if not use a default one
    local theme_file="$HOME/.oh-my-posh/negligible.omp.json"
    if [[ ! -f "$theme_file" ]]; then
        # Use a similar minimal theme if negligible doesn't exist
        local fallback_theme=$(find "$HOME/.oh-my-posh" -name "*.omp.json" | grep -E "(minimal|clean|simple)" | head -1)
        if [[ -n "$fallback_theme" ]]; then
            log_warning "negligible.omp.json not found, using $(basename "$fallback_theme") instead"
            sed -i "s/negligible.omp.json/$(basename "$fallback_theme")/g" "$profile_path"
        fi
    fi
}

# Set up bash integration (optional)
setup_bash_integration() {
    log_info "Setting up bash integration for oh-my-posh..."
    
    local bashrc_addition="
# oh-my-posh integration (if available)
if command -v oh-my-posh &>/dev/null; then
    eval \"\$(oh-my-posh init bash --config ~/.oh-my-posh/negligible.omp.json)\"
fi"
    
    # Add to .bashrc if not already present
    if ! grep -q "oh-my-posh init bash" "$HOME/.bashrc" 2>/dev/null; then
        echo "$bashrc_addition" >> "$HOME/.bashrc"
        log_success "Bash integration configured"
    else
        log_info "Bash integration already configured"
    fi
}

# Display final instructions
show_final_instructions() {
    log_success "Installation completed successfully!"
    echo
    echo -e "${GREEN}Next steps:${NC}"
    echo "1. Restart your terminal or run: source ~/.bashrc"
    echo "2. Start PowerShell with: pwsh"
    echo "3. Your terminal should now display the oh-my-posh theme"
    echo
    echo -e "${BLUE}Configuration details:${NC}"
    echo "• PowerShell profile: ~/.config/powershell/Microsoft.PowerShell_profile.ps1"
    echo "• oh-my-posh themes: ~/.oh-my-posh/"
    echo "• Nerd Font installed: $NERD_FONT_NAME"
    echo
    echo -e "${YELLOW}To customize:${NC}"
    echo "• Edit your PowerShell profile: code ~/.config/powershell/Microsoft.PowerShell_profile.ps1"
    echo "• Browse themes: ls ~/.oh-my-posh/*.omp.json"
    echo "• Change theme: modify the --config parameter in your profile"
    echo
    if command -v pwsh &>/dev/null; then
        local ps_version=$(pwsh -c '$PSVersionTable.PSVersion.ToString()' 2>/dev/null)
        echo -e "${GREEN}PowerShell version installed: $ps_version${NC}"
    fi
}

# Main installation function
main() {
    echo -e "${BLUE}PowerShell Installation Script for Ubuntu 24.04${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --lts)
                INSTALL_LTS=true
                shift
                ;;
            --force)
                FORCE_REINSTALL=true
                shift
                ;;
            --font)
                NERD_FONT_NAME="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --lts          Install LTS version instead of latest stable"
                echo "  --force        Force reinstall even if already installed"
                echo "  --font NAME    Specify Nerd Font name (default: MesloLGM)"
                echo "  --help         Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Show configuration
    echo -e "${BLUE}Configuration:${NC}"
    echo "• Install LTS version: $INSTALL_LTS"
    echo "• Force reinstall: $FORCE_REINSTALL"
    echo "• Nerd Font: $NERD_FONT_NAME"
    echo
    
    # Run installation steps
    check_root
    check_ubuntu_version
    update_system
    install_prerequisites
    install_powershell
    install_nerd_font
    install_oh_my_posh
    configure_powershell
    setup_bash_integration
    show_final_instructions
}

# Run main function with all arguments
main "$@"
