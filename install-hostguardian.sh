#!/bin/bash

# HostGuardian One-Line Installer
# Copyright (c) 2024 HostGuardian

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Version
VERSION="1.0.0"

# Paths
INSTALL_DIR="/usr/local/src/hostguardian"
CPANEL_BASE="/usr/local/cpanel"
LOG_FILE="/var/log/hostguardian_install.log"

# Banner
print_banner() {
    echo -e "${BLUE}"
    echo '╔═══════════════════════════════════════════╗'
    echo '║           HostGuardian Installer          ║'
    echo "║               Version ${VERSION}              ║"
    echo '╚═══════════════════════════════════════════╝'
    echo -e "${NC}"
}

# Logging
log() {
    echo -e "${2:-$NC}$1${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

error() {
    log "$1" "$RED"
    exit 1
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..." "$YELLOW"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root"
    fi

    # Check if running on a cPanel server
    if [ ! -d "$CPANEL_BASE" ]; then
        error "This script must be run on a cPanel server"
    fi

    # Check for required commands
    for cmd in git curl perl mysql wget tar; do
        if ! command -v $cmd >/dev/null 2>&1; then
            error "$cmd is required but not installed"
        fi
    done
}

# Download and extract
download_files() {
    log "Downloading HostGuardian..." "$YELLOW"
    
    cd /usr/local/src
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
    fi
    
    git clone https://github.com/iammaksudul/hostguardian.git
    cd hostguardian
    
    if [ ! -f "install.sh" ]; then
        error "Invalid or corrupted download"
    fi
}

# Install dependencies
install_dependencies() {
    log "Installing dependencies..." "$YELLOW"
    
    # Install required Perl modules
    for module in "JSON::XS" "DBI" "DBD::mysql" "Time::Piece" "Config::IniFiles"; do
        log "Installing Perl module: $module" "$YELLOW"
        $CPANEL_BASE/3rdparty/bin/perl -MCPAN -e "CPAN::Shell->install(\"$module\")"
    done
}

# Run main installer
run_installer() {
    log "Running main installer..." "$YELLOW"
    
    chmod +x install.sh
    ./install.sh
    
    if [ $? -ne 0 ]; then
        error "Installation failed. Check $LOG_FILE for details"
    fi
}

# Verify installation
verify_installation() {
    log "Verifying installation..." "$YELLOW"
    
    # Check if hooks are registered
    if ! $CPANEL_BASE/bin/manage_hooks list | grep -q "HostGuardian"; then
        error "Hook registration failed"
    fi
    
    # Check if database is accessible
    if ! mysql -e "USE hostguardian;" 2>/dev/null; then
        error "Database setup failed"
    fi
    
    # Check if files are in place
    for file in "$CPANEL_BASE/Cpanel/HostGuardian/Hooks.pm" "$CPANEL_BASE/base/hostguardian/hooks.pl"; do
        if [ ! -f "$file" ]; then
            error "Missing required file: $file"
        fi
    done
}

# Main installation process
main() {
    print_banner
    
    # Create log file
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    
    log "Starting HostGuardian installation..." "$GREEN"
    
    check_requirements
    download_files
    install_dependencies
    run_installer
    verify_installation
    
    log "Installation completed successfully!" "$GREEN"
    log "View the logs at: $LOG_FILE"
    log "Access HostGuardian at:"
    log "WHM: https://your-server:2087/cgi/hostguardian/index.cgi"
    log "cPanel: https://your-server:2083/cgi/hostguardian/index.cgi"
}

# Run main function
main 