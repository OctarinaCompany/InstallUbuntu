#!/bin/bash

# =============================================================================
# Automated Node.js, npm & npx Installation Script for Ubuntu 24.04
# =============================================================================
# This script dynamically installs the latest version or LTS version of 
# Node.js, npm, and npx on Ubuntu 24.04 without hardcoding version numbers.
# All operations are fully automated and non-interactive.
#
# Features:
# - Dynamic detection of latest LTS and current versions
# - Non-interactive installation with forced operations
# - Choice between NVM method and NodeSource repository method
# - Automatic system updates and prerequisite installation
# - Comprehensive error handling and logging
# - Profile configuration for persistent environment setup
#
# Usage:
#   bash install_nodejs.sh [lts|latest] [nvm|nodesource]
#   bash install_nodejs.sh                    # Default: LTS via NodeSource
#   bash install_nodejs.sh lts               # LTS via NodeSource
#   bash install_nodejs.sh latest nvm        # Latest via NVM
#
# Author: Generated for Ubuntu 24.04 compatibility
# Date: $(date +%Y-%m-%d)
# =============================================================================

set -eo pipefail  # Exit on error and pipe failures (allow unbound variables for compatibility)

# =============================================================================
# Configuration Variables
# =============================================================================

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_NAME="nodejs-installer"
readonly LOG_FILE="/tmp/${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"
readonly REQUIRED_UBUNTU_VERSION="24.04"

# Default installation parameters
VERSION_TYPE="${1:-lts}"      # lts or latest
INSTALL_METHOD="${2:-nodesource}"  # nvm or nodesource

# NVM configuration
readonly NVM_VERSION="v0.40.2"  # Latest stable version as of 2025
readonly NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"

# =============================================================================
# Utility Functions
# =============================================================================

# Logging function with timestamp and colors
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${CYAN}[INFO]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
        "STEP")
            echo -e "${BLUE}[STEP]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Error handling function
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Installation failed. Check log file: $LOG_FILE"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error_exit "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
}

# Check if user has sudo privileges
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log "INFO" "This script requires sudo privileges. You may be prompted for your password."
        if ! sudo -v; then
            error_exit "Failed to obtain sudo privileges"
        fi
    fi
}

# Verify Ubuntu version compatibility
check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        error_exit "Cannot determine OS version. This script is designed for Ubuntu 24.04"
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        error_exit "This script is designed for Ubuntu. Detected OS: $ID"
    fi
    
    if [[ "$VERSION_ID" != "$REQUIRED_UBUNTU_VERSION" ]]; then
        log "WARNING" "This script is optimized for Ubuntu $REQUIRED_UBUNTU_VERSION. Detected: $VERSION_ID"
        log "WARNING" "Continuing anyway, but some features may not work as expected."
    fi
    
    log "SUCCESS" "Ubuntu version check passed: $VERSION_ID"
}

# Update system packages
update_system() {
    log "STEP" "Updating system packages"
    
    # Update package lists
    if ! sudo apt update -qq; then
        error_exit "Failed to update package lists"
    fi
    
    # Upgrade existing packages non-interactively
    if ! sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq; then
        error_exit "Failed to upgrade system packages"
    fi
    
    log "SUCCESS" "System packages updated successfully"
}

# Install prerequisite packages
install_prerequisites() {
    log "STEP" "Installing prerequisite packages"
    
    local packages=(
        "curl"
        "wget"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "apt-transport-https"
        "software-properties-common"
        "build-essential"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log "INFO" "Installing $package"
            if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y -qq "$package"; then
                error_exit "Failed to install $package"
            fi
        else
            log "INFO" "$package is already installed"
        fi
    done
    
    log "SUCCESS" "All prerequisite packages installed"
}

# Remove existing Node.js installations to prevent conflicts
cleanup_existing_nodejs() {
    log "STEP" "Cleaning up existing Node.js installations"
    
    # Remove apt-installed Node.js
    if dpkg -l | grep -q nodejs; then
        log "INFO" "Removing existing Node.js installation via apt"
        sudo apt remove --purge -y nodejs npm 2>/dev/null || true
        sudo apt autoremove -y 2>/dev/null || true
    fi
    
    # Clean up any NodeSource repositories
    if [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
        log "INFO" "Removing existing NodeSource repository"
        sudo rm -f /etc/apt/sources.list.d/nodesource.list
    fi
    
    # Remove NodeSource GPG key
    if [[ -f /etc/apt/keyrings/nodesource.gpg ]]; then
        sudo rm -f /etc/apt/keyrings/nodesource.gpg
    fi
    
    log "SUCCESS" "Cleanup completed"
}

# Get the latest Node.js version dynamically
get_latest_nodejs_version() {
    log "INFO" "Detecting latest Node.js versions"
    
    local latest_version
    local lts_version
    
    # Get latest version from Node.js API
    latest_version=$(curl -s https://nodejs.org/dist/index.json | grep -o '"version":"[^"]*' | head -n1 | sed 's/"version":"v//')
    
    # Get LTS version from Node.js API
    lts_version=$(curl -s https://nodejs.org/dist/index.json | grep -A1 '"lts":' | grep -v 'false' | head -n1 | grep -o '"version":"[^"]*' | sed 's/"version":"v//')
    
    if [[ -z "$latest_version" || -z "$lts_version" ]]; then
        error_exit "Failed to detect Node.js versions from API"
    fi
    
    log "INFO" "Latest Node.js version: v$latest_version"
    log "INFO" "Latest LTS Node.js version: v$lts_version"
    
    if [[ "$VERSION_TYPE" == "latest" ]]; then
        echo "$latest_version"
    else
        echo "$lts_version"
    fi
}

# Install Node.js via NodeSource repository
install_via_nodesource() {
    log "STEP" "Installing Node.js via NodeSource repository"
    
    # Get version information once and store it
    log "INFO" "Detecting latest Node.js versions"
    local latest_version
    local lts_version
    
    # Get latest version from Node.js API
    latest_version=$(curl -s https://nodejs.org/dist/index.json | grep -o '"version":"[^"]*' | head -n1 | sed 's/"version":"v//')
    
    # Get LTS version from Node.js API  
    lts_version=$(curl -s https://nodejs.org/dist/index.json | grep -A1 '"lts":' | grep -v 'false' | head -n1 | grep -o '"version":"[^"]*' | sed 's/"version":"v//')
    
    if [[ -z "$latest_version" || -z "$lts_version" ]]; then
        error_exit "Failed to detect Node.js versions from API"
    fi
    
    log "INFO" "Latest Node.js version: v$latest_version"
    log "INFO" "Latest LTS Node.js version: v$lts_version"
    
    local target_version
    if [[ "$VERSION_TYPE" == "latest" ]]; then
        target_version="$latest_version"
    else
        target_version="$lts_version"
    fi
    
    local major_version
    major_version=$(echo "$target_version" | cut -d. -f1)
    
    log "INFO" "Target Node.js version: v$target_version (major: $major_version)"
    
    # Download and execute NodeSource setup script
    log "INFO" "Setting up NodeSource repository for Node.js $major_version"
    
    local setup_script_url="https://deb.nodesource.com/setup_${major_version}.x"
    
    if ! curl -fsSL "$setup_script_url" | sudo -E bash -; then
        error_exit "Failed to setup NodeSource repository"
    fi
    
    # Update package lists after adding repository
    if ! sudo apt update -qq; then
        error_exit "Failed to update package lists after adding NodeSource repository"
    fi
    
    # Install Node.js and npm
    log "INFO" "Installing Node.js and npm"
    if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y -qq nodejs; then
        error_exit "Failed to install Node.js and npm"
    fi
    
    log "SUCCESS" "Node.js installed successfully via NodeSource"
}
    
    # Update package lists after adding repository
    if ! sudo apt update -qq; then
        error_exit "Failed to update package lists after adding NodeSource repository"
    fi
    
    # Install Node.js and npm
    log "INFO" "Installing Node.js and npm"
    if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y -qq nodejs; then
        error_exit "Failed to install Node.js and npm"
    fi
    
    log "SUCCESS" "Node.js installed successfully via NodeSource"
}

# Install Node.js via NVM
install_via_nvm() {
    log "STEP" "Installing Node.js via NVM (Node Version Manager)"
    
    # Get version information once and store it
    log "INFO" "Detecting latest Node.js versions"
    local latest_version
    local lts_version
    
    # Get latest version from Node.js API
    latest_version=$(curl -s https://nodejs.org/dist/index.json | grep -o '"version":"[^"]*' | head -n1 | sed 's/"version":"v//')
    
    # Get LTS version from Node.js API
    lts_version=$(curl -s https://nodejs.org/dist/index.json | grep -A1 '"lts":' | grep -v 'false' | head -n1 | grep -o '"version":"[^"]*' | sed 's/"version":"v//')
    
    if [[ -z "$latest_version" || -z "$lts_version" ]]; then
        error_exit "Failed to detect Node.js versions from API"
    fi
    
    log "INFO" "Latest Node.js version: v$latest_version"
    log "INFO" "Latest LTS Node.js version: v$lts_version"
    
    local target_version
    if [[ "$VERSION_TYPE" == "latest" ]]; then
        target_version="$latest_version"
    else
        target_version="$lts_version"
    fi
    
    log "INFO" "Target Node.js version: v$target_version"
    
    # Download and install NVM
    log "INFO" "Downloading and installing NVM $NVM_VERSION"
    
    export NVM_DIR="$HOME/.nvm"
    
    # Remove existing NVM installation if present
    if [[ -d "$NVM_DIR" ]]; then
        log "INFO" "Removing existing NVM installation"
        rm -rf "$NVM_DIR"
    fi
    
    # Download and install NVM
    if ! curl -o- "$NVM_INSTALL_URL" | bash; then
        error_exit "Failed to install NVM"
    fi
    
    # Load NVM into current session
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
    
    # Verify NVM installation
    if ! command -v nvm &> /dev/null; then
        error_exit "NVM installation failed - command not found"
    fi
    
    log "SUCCESS" "NVM installed successfully"
    
    # Install Node.js using NVM
    log "INFO" "Installing Node.js v$target_version using NVM"
    
    if [[ "$VERSION_TYPE" == "latest" ]]; then
        if ! nvm install node; then
            error_exit "Failed to install latest Node.js via NVM"
        fi
        if ! nvm use node; then
            error_exit "Failed to use latest Node.js via NVM"
        fi
        if ! nvm alias default node; then
            error_exit "Failed to set default Node.js version via NVM"
        fi
    else
        # Install LTS version
        if ! nvm install --lts; then
            error_exit "Failed to install LTS Node.js via NVM"
        fi
        if ! nvm use --lts; then
            error_exit "Failed to use LTS Node.js via NVM"
        fi
        if ! nvm alias default lts/*; then
            error_exit "Failed to set default Node.js version via NVM"
        fi
    fi
    
    log "SUCCESS" "Node.js installed successfully via NVM"
}

# Configure shell profile for persistent environment
configure_profile() {
    log "STEP" "Configuring shell profile for persistent environment"
    
    local shell_name
    shell_name=$(basename "$SHELL")
    local profile_file
    
    case "$shell_name" in
        "bash")
            profile_file="$HOME/.bashrc"
            ;;
        "zsh")
            profile_file="$HOME/.zshrc"
            ;;
        *)
            profile_file="$HOME/.profile"
            ;;
    esac
    
    log "INFO" "Detected shell: $shell_name, using profile: $profile_file"
    
    if [[ "$INSTALL_METHOD" == "nvm" ]]; then
        # NVM configuration
        local nvm_config='
# NVM Configuration - Added by Node.js installer script
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion'
        
        if ! grep -q "NVM Configuration" "$profile_file" 2>/dev/null; then
            echo "$nvm_config" >> "$profile_file"
            log "SUCCESS" "NVM configuration added to $profile_file"
        else
            log "INFO" "NVM configuration already exists in $profile_file"
        fi
    else
        # NodeSource configuration (Node.js should be in PATH automatically)
        log "INFO" "Node.js installed via NodeSource - no additional profile configuration needed"
    fi
    
    # Add npm global bin to PATH if not already present
    local npm_global_bin
    if command -v npm &> /dev/null; then
        npm_global_bin=$(npm config get prefix 2>/dev/null)/bin
        if [[ -n "$npm_global_bin" ]] && [[ "$PATH" != *"$npm_global_bin"* ]]; then
            echo "export PATH=\"$npm_global_bin:\$PATH\"" >> "$profile_file"
            log "SUCCESS" "npm global bin path added to $profile_file"
        fi
    fi
}

# Verify installation success
verify_installation() {
    log "STEP" "Verifying installation"
    
    # Source the profile to ensure environment is loaded
    if [[ "$INSTALL_METHOD" == "nvm" ]]; then
        export NVM_DIR="$HOME/.nvm"
        [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        error_exit "Node.js installation verification failed - command not found"
    fi
    
    local node_version
    node_version=$(node --version)
    log "SUCCESS" "Node.js installed: $node_version"
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        error_exit "npm installation verification failed - command not found"
    fi
    
    local npm_version
    npm_version=$(npm --version)
    log "SUCCESS" "npm installed: v$npm_version"
    
    # Check npx (comes with npm)
    if ! command -v npx &> /dev/null; then
        error_exit "npx installation verification failed - command not found"
    fi
    
    local npx_version
    npx_version=$(npx --version)
    log "SUCCESS" "npx installed: v$npx_version"
    
    # Display installation summary
    echo ""
    echo -e "${GREEN}=== INSTALLATION SUMMARY ===${NC}"
    echo -e "${CYAN}Node.js Version:${NC} $node_version"
    echo -e "${CYAN}npm Version:${NC} v$npm_version"
    echo -e "${CYAN}npx Version:${NC} v$npx_version"
    echo -e "${CYAN}Installation Method:${NC} $INSTALL_METHOD"
    echo -e "${CYAN}Version Type:${NC} $VERSION_TYPE"
    echo -e "${CYAN}Log File:${NC} $LOG_FILE"
    echo ""
}

# Display usage information
usage() {
    echo "Usage: $0 [VERSION_TYPE] [INSTALL_METHOD]"
    echo ""
    echo "VERSION_TYPE:"
    echo "  lts      Install the latest LTS (Long Term Support) version (default)"
    echo "  latest   Install the latest current version"
    echo ""
    echo "INSTALL_METHOD:"
    echo "  nodesource  Install via NodeSource repository (default)"
    echo "  nvm         Install via Node Version Manager (NVM)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Install LTS via NodeSource"
    echo "  $0 lts               # Install LTS via NodeSource"
    echo "  $0 latest nvm        # Install latest via NVM"
    echo "  $0 lts nvm           # Install LTS via NVM"
    echo ""
}

# Validate command line arguments
validate_arguments() {
    if [[ "$VERSION_TYPE" != "lts" && "$VERSION_TYPE" != "latest" ]]; then
        log "ERROR" "Invalid version type: $VERSION_TYPE"
        usage
        exit 1
    fi
    
    if [[ "$INSTALL_METHOD" != "nvm" && "$INSTALL_METHOD" != "nodesource" ]]; then
        log "ERROR" "Invalid installation method: $INSTALL_METHOD"
        usage
        exit 1
    fi
    
    log "INFO" "Installation parameters: Version=$VERSION_TYPE, Method=$INSTALL_METHOD"
}

# Main installation function
main() {
    # Display header
    echo -e "${BLUE}"
    echo "============================================================================="
    echo "  Automated Node.js, npm & npx Installation Script for Ubuntu 24.04"
    echo "============================================================================="
    echo -e "${NC}"
    
    # Initialize logging
    log "INFO" "Starting Node.js installation script"
    log "INFO" "Log file: $LOG_FILE"
    
    # Validate arguments
    validate_arguments
    
    # Perform pre-installation checks
    check_root
    check_sudo
    check_ubuntu_version
    
    # Prepare system
    update_system
    install_prerequisites
    cleanup_existing_nodejs
    
    # Install Node.js based on selected method
    if [[ "$INSTALL_METHOD" == "nvm" ]]; then
        install_via_nvm
    else
        install_via_nodesource
    fi
    
    # Post-installation configuration
    configure_profile
    verify_installation
    
    # Final message
    echo -e "${GREEN}"
    echo "============================================================================="
    echo "  Installation completed successfully!"
    echo "============================================================================="
    echo -e "${NC}"
    echo ""
    echo "To start using Node.js in your current terminal session:"
    if [[ "$INSTALL_METHOD" == "nvm" ]]; then
        echo -e "${YELLOW}source ~/.nvm/nvm.sh${NC}"
    fi
    echo -e "${YELLOW}node --version${NC}"
    echo -e "${YELLOW}npm --version${NC}"
    echo ""
    echo "For new terminal sessions, Node.js will be available automatically."
    echo ""
    
    log "SUCCESS" "Node.js installation script completed successfully"
}

# Handle script interruption
trap 'error_exit "Script interrupted by user"' INT TERM

# Execute main function
main "$@"
