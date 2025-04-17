#!/bin/bash

# HostGuardian One-Line Uninstaller
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
LOG_FILE="/var/log/hostguardian_uninstall.log"

# Banner
print_banner() {
    echo -e "${BLUE}"
    echo '╔═══════════════════════════════════════════╗'
    echo '║          HostGuardian Uninstaller         ║'
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

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root"
    fi
}

# Unregister hooks
unregister_hooks() {
    log "Unregistering hooks..." "$YELLOW"
    
    HOOKS=(
        "Cpanel:BACKUP:pre"
        "Cpanel:BACKUP:post"
        "Cpanel:RESTORE:pre"
        "Cpanel:RESTORE:post"
        "Whostmgr:Suspend:pre"
        "Whostmgr:Unsuspend:post"
        "Whostmgr:Terminate:pre"
    )
    
    for hook in "${HOOKS[@]}"; do
        IFS=: read -r category event stage <<< "$hook"
        $CPANEL_BASE/bin/manage_hooks delete module "Cpanel::HostGuardian::Hooks" \
            --category="$category" --event="$event" --stage="$stage" 2>/dev/null || true
    done
}

# Remove files
remove_files() {
    log "Removing files..." "$YELLOW"
    
    # Remove source files
    rm -rf "$INSTALL_DIR"
    
    # Remove installed components
    rm -rf "$CPANEL_BASE/Cpanel/HostGuardian"
    rm -rf "$CPANEL_BASE/base/hostguardian"
    rm -rf "$CPANEL_BASE/whostmgr/docroot/cgi/hostguardian"
}

# Remove database
remove_database() {
    log "Removing database..." "$YELLOW"
    
    mysql -e "DROP DATABASE IF EXISTS hostguardian;"
    mysql -e "DROP USER IF EXISTS 'hostguardian'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
}

# Clean up logs
cleanup_logs() {
    log "Cleaning up logs..." "$YELLOW"
    
    rm -f /var/log/hostguardian*.log
}

# Verify uninstallation
verify_uninstallation() {
    log "Verifying uninstallation..." "$YELLOW"
    
    # Check if hooks are removed
    if $CPANEL_BASE/bin/manage_hooks list | grep -q "HostGuardian"; then
        error "Failed to remove hooks"
    fi
    
    # Check if database is removed
    if mysql -e "USE hostguardian;" 2>/dev/null; then
        error "Failed to remove database"
    fi
    
    # Check if files are removed
    for dir in "$CPANEL_BASE/Cpanel/HostGuardian" "$CPANEL_BASE/base/hostguardian"; do
        if [ -d "$dir" ]; then
            error "Failed to remove directory: $dir"
        fi
    done
}

# Main uninstallation process
main() {
    print_banner
    
    # Create log file
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    
    log "Starting HostGuardian uninstallation..." "$GREEN"
    
    check_root
    unregister_hooks
    remove_files
    remove_database
    cleanup_logs
    verify_uninstallation
    
    log "Uninstallation completed successfully!" "$GREEN"
    log "View the logs at: $LOG_FILE"
}

# Run main function
main 