#!/bin/bash

#==============================================================================
# AUTOMATED NODE.JS INSTALLATION SCRIPT FOR UBUNTU 24.04
#==============================================================================
# Description: Fully automated script to install the latest or LTS Node.js 
#              version using NVM (Node Version Manager) without hardcoding versions
# Author: OctarinaCompany
# Version: 2.0
# Compatible: Ubuntu 24.04 LTS
# Requirements: curl, wget, git (auto-installed if missing)
# Usage: curl -H 'Cache-Control: no-cache' -fsSL https://raw.githubusercontent.com/OctarinaCompany/InstallUbuntu/refs/heads/main/scripts/install_nodejs.sh | bash
#==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_NAME="Node.js Installation Script"
readonly SCRIPT_VERSION="2.0"
readonly NVM_VERSION="v0.40.3"  # Latest stable NVM version
readonly LOG_FILE="/tmp/nodejs_install_$(date +%Y%m%d_%H%M%S).log"

# Installation preferences (can be overridden by environment variables)
INSTALL_LTS="${INSTALL_LTS:-true}"           # Install LTS by default
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"  # Force reinstall if already installed
SILENT_MODE="${SILENT_MODE:-false}"          # Show output by default
AUTO_YES="${AUTO_YES:-true}"                 # Auto-confirm all prompts

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Enhanced logging function with timestamp and levels
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "${level}" in
        "INFO")  echo -e "${CYAN}[${timestamp}] [INFO]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
        "WARN")  echo -e "${YELLOW}[${timestamp}] [WARN]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
        "ERROR") echo -e "${RED}[${timestamp}] [ERROR]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
        "SUCCESS") echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
        "DEBUG") echo -e "${PURPLE}[${timestamp}] [DEBUG]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
        *) echo -e "${BLUE}[${timestamp}] [LOG]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
    esac
}

# Progress indicator for long-running operations
show_progress() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Check if script is run with appropriate permissions
check_permissions() {
    log "INFO" "Checking script execution permissions..."
    
    if [[ $EUID -eq 0 ]]; then
        log "WARN" "Running as root user. This script should be run as a regular user with sudo privileges."
        log "WARN" "NVM installation as root is not recommended for security reasons."
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "ERROR" "Installation cancelled by user."
            exit 1
        fi
    fi
    
    # Check sudo access without prompting for password if possible
    if sudo -n true 2>/dev/null; then
        log "SUCCESS" "Sudo access confirmed."
    else
        log "INFO" "Testing sudo access (password may be required)..."
        if ! sudo -v; then
            log "ERROR" "This script requires sudo privileges for system package installation."
            exit 1
        fi
        log "SUCCESS" "Sudo access granted."
    fi
}

# Comprehensive system compatibility check
check_system_compatibility() {
    log "INFO" "Performing system compatibility checks..."
    
    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        log "INFO" "Detected OS: ${NAME} ${VERSION}"
        
        if [[ "${ID}" != "ubuntu" ]]; then
            log "WARN" "This script is optimized for Ubuntu. Detected: ${ID}"
            log "WARN" "Proceeding anyway, but some features may not work as expected."
        fi
        
        # Extract major version number
        local version_id=${VERSION_ID%.*}
        if [[ "${version_id}" -lt 20 ]]; then
            log "ERROR" "Ubuntu 20.04 or later is required. Detected: ${VERSION_ID}"
            exit 1
        fi
        
        if [[ "${VERSION_ID}" == "24.04" ]]; then
            log "SUCCESS" "Ubuntu 24.04 detected - optimal compatibility."
        fi
    else
        log "WARN" "Cannot determine OS version. Proceeding with installation attempt."
    fi
    
    # Check system architecture
    local arch=$(uname -m)
    log "INFO" "System architecture: ${arch}"
    
    case "${arch}" in
        x86_64|amd64)
            log "SUCCESS" "64-bit x86 architecture detected - fully supported."
            ;;
        aarch64|arm64)
            log "SUCCESS" "ARM64 architecture detected - supported."
            ;;
        armv7l)
            log "WARN" "ARMv7 detected - limited Node.js version support."
            ;;
        *)
            log "WARN" "Unsupported architecture: ${arch}. Installation may fail."
            ;;
    esac
    
    # Check available disk space (require at least 1GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB in KB
    
    if [[ ${available_space} -lt ${required_space} ]]; then
        log "WARN" "Low disk space: $(( available_space / 1024 ))MB available. At least 1GB recommended."
    else
        log "SUCCESS" "Sufficient disk space available: $(( available_space / 1024 / 1024 ))GB"
    fi
}

# Install essential system dependencies
install_dependencies() {
    log "INFO" "Installing essential system dependencies..."
    
    # Update package list
    log "INFO" "Updating package repository lists..."
    if ! sudo apt-get update -qq > /dev/null 2>&1; then
        log "ERROR" "Failed to update package lists. Check your internet connection."
        exit 1
    fi
    
    # Essential packages for Node.js development and NVM
    local dependencies=(
        "curl"              # Required for NVM installation and npm registry access
        "wget"              # Alternative download tool
        "git"               # Required for NVM and version control
        "build-essential"   # Compilation tools for native modules
        "libssl-dev"        # SSL/TLS library for secure connections
        "ca-certificates"   # Certificate authorities for HTTPS
        "gnupg"             # GNU Privacy Guard for package verification
        "lsb-release"       # Linux Standard Base info
        "software-properties-common"  # Manage PPAs and repositories
    )
    
    log "INFO" "Installing required packages: ${dependencies[*]}"
    
    # Use DEBIAN_FRONTEND=noninteractive to prevent interactive prompts
    export DEBIAN_FRONTEND=noninteractive
    
    if sudo apt-get install -y --no-install-recommends "${dependencies[@]}" >> "${LOG_FILE}" 2>&1; then
        log "SUCCESS" "All dependencies installed successfully."
    else
        log "ERROR" "Failed to install some dependencies. Check ${LOG_FILE} for details."
        exit 1
    fi
    
    # Verify critical dependencies
    for cmd in curl git; do
        if ! command -v "${cmd}" &> /dev/null; then
            log "ERROR" "Critical dependency '${cmd}' is not available after installation."
            exit 1
        fi
    done
    
    log "SUCCESS" "All critical dependencies verified."
}

# Remove existing Node.js installations to prevent conflicts
cleanup_existing_nodejs() {
    log "INFO" "Checking for existing Node.js installations..."
    
    # Check for system-installed Node.js
    if command -v node &> /dev/null || command -v nodejs &> /dev/null; then
        local existing_version=""
        if command -v node &> /dev/null; then
            existing_version=$(node --version 2>/dev/null || echo "unknown")
        elif command -v nodejs &> /dev/null; then
            existing_version=$(nodejs --version 2>/dev/null || echo "unknown")
        fi
        
        log "WARN" "Existing Node.js installation detected: ${existing_version}"
        
        if [[ "${FORCE_REINSTALL}" == "true" ]]; then
            log "INFO" "Force reinstall enabled. Removing existing Node.js installations..."
            
            # Remove system packages
            sudo apt-get remove --purge -y nodejs npm node 2>/dev/null || true
            sudo apt-get autoremove -y 2>/dev/null || true
            
            # Remove common installation directories
            sudo rm -rf /usr/local/{lib/node{,_modules},bin,share/man}/{npm*,node*} 2>/dev/null || true
            sudo rm -rf /usr/local/bin/npm /usr/local/share/man/man1/node* 2>/dev/null || true
            sudo rm -rf /usr/local/lib/dtrace/node.d 2>/dev/null || true
            sudo rm -rf ~/.npm 2>/dev/null || true
            
            log "SUCCESS" "Existing Node.js installations removed."
        else
            log "WARN" "Existing installation found. Use FORCE_REINSTALL=true to remove it."
            log "WARN" "Continuing with NVM installation - it will manage versions independently."
        fi
    else
        log "SUCCESS" "No existing Node.js installations detected."
    fi
    
    # Check for existing NVM installation
    if [[ -d "${HOME}/.nvm" ]]; then
        log "WARN" "Existing NVM installation found at ${HOME}/.nvm"
        
        if [[ "${FORCE_REINSTALL}" == "true" ]]; then
            log "INFO" "Removing existing NVM installation..."
            rm -rf "${HOME}/.nvm"
            log "SUCCESS" "Existing NVM installation removed."
        else
            log "INFO" "Updating existing NVM installation..."
        fi
    fi
}

# Install or update NVM (Node Version Manager)
install_nvm() {
    log "INFO" "Installing NVM (Node Version Manager) version ${NVM_VERSION}..."
    
    # Download and install NVM using the official installation script
    local nvm_install_url="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
    
    log "INFO" "Downloading NVM installation script from: ${nvm_install_url}"
    
    # Download with retries and proper error handling
    local max_retries=3
    local retry_count=0
    
    while [[ ${retry_count} -lt ${max_retries} ]]; do
        if curl -o- "${nvm_install_url}" | bash >> "${LOG_FILE}" 2>&1; then
            log "SUCCESS" "NVM installation script executed successfully."
            break
        else
            retry_count=$((retry_count + 1))
            log "WARN" "NVM installation attempt ${retry_count} failed. Retrying..."
            sleep 2
        fi
        
        if [[ ${retry_count} -eq ${max_retries} ]]; then
            log "ERROR" "Failed to install NVM after ${max_retries} attempts."
            exit 1
        fi
    done
    
    # Set up NVM environment for current session
    export NVM_DIR="${HOME}/.nvm"
    
    # Source NVM script
    if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
        source "${NVM_DIR}/nvm.sh"
        log "SUCCESS" "NVM environment loaded successfully."
    else
        log "ERROR" "NVM installation failed - nvm.sh not found."
        exit 1
    fi
    
    # Verify NVM installation
    if command -v nvm &> /dev/null; then
        local nvm_version=$(nvm --version)
        log "SUCCESS" "NVM ${nvm_version} installed and ready to use."
    else
        log "ERROR" "NVM installation verification failed."
        exit 1
    fi
    
    # Load bash completion if available
    if [[ -s "${NVM_DIR}/bash_completion" ]]; then
        source "${NVM_DIR}/bash_completion"
        log "INFO" "NVM bash completion loaded."
    fi
}

# Configure shell profile for automatic NVM loading
configure_shell_profile() {
    log "INFO" "Configuring shell profile for automatic NVM loading..."
    
    # Detect current shell
    local current_shell=$(basename "${SHELL}")
    local profile_files=()
    
    case "${current_shell}" in
        bash)
            profile_files=("${HOME}/.bashrc" "${HOME}/.bash_profile" "${HOME}/.profile")
            ;;
        zsh)
            profile_files=("${HOME}/.zshrc" "${HOME}/.zprofile")
            ;;
        fish)
            # Fish shell requires different setup - skip for now
            log "WARN" "Fish shell detected. Manual configuration may be required."
            return 0
            ;;
        *)
            profile_files=("${HOME}/.profile")
            log "WARN" "Unknown shell: ${current_shell}. Using .profile for configuration."
            ;;
    esac
    
    # NVM configuration lines
    local nvm_config='
# NVM (Node Version Manager) Configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion'
    
    # Add configuration to appropriate profile files
    for profile_file in "${profile_files[@]}"; do
        if [[ -f "${profile_file}" ]] || [[ "${profile_file}" == "${HOME}/.bashrc" ]]; then
            # Create file if it doesn't exist (especially for .bashrc)
            touch "${profile_file}"
            
            # Check if NVM config already exists
            if ! grep -q "NVM_DIR" "${profile_file}" 2>/dev/null; then
                echo "${nvm_config}" >> "${profile_file}"
                log "SUCCESS" "NVM configuration added to ${profile_file}"
            else
                log "INFO" "NVM configuration already exists in ${profile_file}"
            fi
        fi
    done
    
    log "SUCCESS" "Shell profile configuration completed."
}

# Determine which Node.js version to install
determine_nodejs_version() {
    log "INFO" "Determining optimal Node.js version to install..."
    
    # Refresh NVM's remote version list
    log "INFO" "Refreshing Node.js version list from remote..."
    nvm ls-remote --no-colors > /tmp/nvm_versions.txt 2>&1 || {
        log "ERROR" "Failed to fetch Node.js version list. Check internet connection."
        exit 1
    }
    
    if [[ "${INSTALL_LTS}" == "true" ]]; then
        # Get latest LTS version
        local lts_version=$(nvm ls-remote --lts --no-colors 2>/dev/null | tail -1 | awk '{print $1}' | sed 's/^v//')
        
        if [[ -n "${lts_version}" ]]; then
            NODE_VERSION="lts/*"
            log "SUCCESS" "Latest LTS version determined: ${lts_version}"
        else
            log "ERROR" "Failed to determine latest LTS version."
            exit 1
        fi
    else
        # Get latest stable version
        local latest_version=$(nvm ls-remote --no-colors 2>/dev/null | tail -1 | awk '{print $1}' | sed 's/^v//')
        
        if [[ -n "${latest_version}" ]]; then
            NODE_VERSION="node"
            log "SUCCESS" "Latest stable version determined: ${latest_version}"
        else
            log "ERROR" "Failed to determine latest stable version."
            exit 1
        fi
    fi
    
    # Clean up temporary file
    rm -f /tmp/nvm_versions.txt
}

# Install Node.js using NVM
install_nodejs() {
    log "INFO" "Installing Node.js version: ${NODE_VERSION}"
    
    # Install Node.js with progress indication
    log "INFO" "Downloading and installing Node.js (this may take a few minutes)..."
    
    # Capture both stdout and stderr for better error reporting
    if nvm install "${NODE_VERSION}" >> "${LOG_FILE}" 2>&1; then
        log "SUCCESS" "Node.js installation completed successfully."
    else
        log "ERROR" "Node.js installation failed. Check ${LOG_FILE} for details."
        exit 1
    fi
    
    # Set the installed version as default
    if nvm alias default "${NODE_VERSION}" >> "${LOG_FILE}" 2>&1; then
        log "SUCCESS" "Node.js version set as default."
    else
        log "WARN" "Failed to set Node.js as default version."
    fi
    
    # Use the installed version immediately
    if nvm use "${NODE_VERSION}" >> "${LOG_FILE}" 2>&1; then
        log "SUCCESS" "Switched to Node.js version: ${NODE_VERSION}"
    else
        log "ERROR" "Failed to switch to installed Node.js version."
        exit 1
    fi
}

# Verify the installation and display version information
verify_installation() {
    log "INFO" "Verifying Node.js installation..."
    
    # Ensure we're using the NVM-installed Node.js
    source "${NVM_DIR}/nvm.sh"
    nvm use "${NODE_VERSION}" > /dev/null 2>&1
    
    # Get version information
    local node_version=""
    local npm_version=""
    local npx_version=""
    
    if command -v node &> /dev/null; then
        node_version=$(node --version 2>/dev/null || echo "Not available")
        log "SUCCESS" "Node.js version: ${node_version}"
    else
        log "ERROR" "Node.js command not found after installation."
        return 1
    fi
    
    if command -v npm &> /dev/null; then
        npm_version=$(npm --version 2>/dev/null || echo "Not available")
        log "SUCCESS" "npm version: ${npm_version}"
    else
        log "ERROR" "npm command not found after installation."
        return 1
    fi
    
    if command -v npx &> /dev/null; then
        npx_version=$(npx --version 2>/dev/null || echo "Not available")
        log "SUCCESS" "npx version: ${npx_version}"
    else
        log "WARN" "npx command not found - may need to update npm."
    fi
    
    # Display installation summary
    echo
    echo "======================================================================"
    echo -e "${GREEN}        NODE.JS INSTALLATION COMPLETED SUCCESSFULLY${NC}"
    echo "======================================================================"
    echo -e "${CYAN}Node.js Version:${NC} ${node_version}"
    echo -e "${CYAN}npm Version:${NC}     ${npm_version}"
    echo -e "${CYAN}npx Version:${NC}     ${npx_version}"
    echo -e "${CYAN}Installation Path:${NC} ${HOME}/.nvm"
    echo -e "${CYAN}Log File:${NC}       ${LOG_FILE}"
    echo "======================================================================"
    echo
    
    # Test basic functionality
    log "INFO" "Testing Node.js functionality..."
    
    if echo "console.log('Node.js is working correctly!');" | node > /dev/null 2>&1; then
        log "SUCCESS" "Node.js functionality test passed."
    else
        log "ERROR" "Node.js functionality test failed."
        return 1
    fi
    
    # Display usage instructions
    echo -e "${YELLOW}USAGE INSTRUCTIONS:${NC}"
    echo "• Open a new terminal session or run: source ~/.bashrc"
    echo "• Check available Node.js versions: nvm ls-remote"
    echo "• Install another version: nvm install <version>"
    echo "• Switch between versions: nvm use <version>"
    echo "• Set default version: nvm alias default <version>"
    echo "• Current version: nvm current"
    echo
    
    return 0
}

# Configure npm for optimal performance and security
configure_npm() {
    log "INFO" "Configuring npm for optimal performance and security..."
    
    # Ensure we're using the NVM-installed npm
    source "${NVM_DIR}/nvm.sh"
    nvm use "${NODE_VERSION}" > /dev/null 2>&1
    
    # Configure npm settings
    local npm_configs=(
        "fund=false"                    # Disable funding messages
        "audit-level=moderate"          # Set audit level
        "save-exact=true"              # Save exact versions in package.json
        "engine-strict=true"           # Enforce engine requirements
        "progress=true"                # Show progress indicators
        "registry=https://registry.npmjs.org/"  # Ensure official registry
    )
    
    for config in "${npm_configs[@]}"; do
        if npm config set "${config}" >> "${LOG_FILE}" 2>&1; then
            log "INFO" "npm config set: ${config}"
        else
            log "WARN" "Failed to set npm config: ${config}"
        fi
    done
    
    # Update npm to latest version
    log "INFO" "Updating npm to the latest version..."
    if npm install -g npm@latest >> "${LOG_FILE}" 2>&1; then
        local new_npm_version=$(npm --version)
        log "SUCCESS" "npm updated to version: ${new_npm_version}"
    else
        log "WARN" "Failed to update npm to latest version."
    fi
    
    log "SUCCESS" "npm configuration completed."
}

# Main installation function
main() {
    echo
    echo "======================================================================"
    echo -e "${BLUE}       ${SCRIPT_NAME} v${SCRIPT_VERSION}${NC}"
    echo "======================================================================"
    echo -e "${CYAN}Target System:${NC} Ubuntu 24.04"
    echo -e "${CYAN}Installation Method:${NC} NVM (Node Version Manager)"
    echo -e "${CYAN}Version Strategy:${NC} $([ "${INSTALL_LTS}" == "true" ] && echo "Latest LTS" || echo "Latest Stable")"
    echo -e "${CYAN}Log File:${NC} ${LOG_FILE}"
    echo "======================================================================"
    echo
    
    # Create log file with header
    cat > "${LOG_FILE}" << EOF
====================================================================
Node.js Installation Script Log
Date: $(date)
User: $(whoami)
System: $(uname -a)
====================================================================

EOF
    
    log "INFO" "Starting Node.js installation process..."
    
    # Execute installation steps
    check_permissions
    check_system_compatibility
    install_dependencies
    cleanup_existing_nodejs
    install_nvm
    configure_shell_profile
    determine_nodejs_version
    install_nodejs
    configure_npm
    
    # Final verification
    if verify_installation; then
        log "SUCCESS" "Node.js installation process completed successfully!"
        echo -e "${GREEN}Installation completed! Please open a new terminal session to start using Node.js.${NC}"
        exit 0
    else
        log "ERROR" "Installation verification failed."
        exit 1
    fi
}

# Error handler
error_handler() {
    local line_number=$1
    log "ERROR" "Script failed at line ${line_number}"
    log "ERROR" "Installation process terminated unexpectedly."
    echo -e "${RED}Installation failed. Check ${LOG_FILE} for details.${NC}"
    exit 1
}

# Set up error handling
trap 'error_handler ${LINENO}' ERR

# Handle script interruption
cleanup_on_interrupt() {
    log "WARN" "Installation interrupted by user."
    echo -e "${YELLOW}Installation cancelled.${NC}"
    exit 130
}

trap cleanup_on_interrupt SIGINT SIGTERM

#==============================================================================
# SCRIPT EXECUTION
#==============================================================================

# Parse command line arguments (if any)
while [[ $# -gt 0 ]]; do
    case $1 in
        --lts)
            INSTALL_LTS="true"
            shift
            ;;
        --latest)
            INSTALL_LTS="false"
            shift
            ;;
        --force)
            FORCE_REINSTALL="true"
            shift
            ;;
        --silent)
            SILENT_MODE="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --lts      Install latest LTS version (default)"
            echo "  --latest   Install latest stable version"
            echo "  --force    Force reinstall if already installed"
            echo "  --silent   Run in silent mode"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log "WARN" "Unknown option: $1"
            shift
            ;;
    esac
done

# Run main installation function
main
