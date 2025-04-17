#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Log file and state file
LOG_FILE="/var/log/hostguardian_install.log"
INSTALL_STATE_FILE="/usr/local/cpanel/base/hostguardian/.install_state"
BACKUP_DIR="/usr/local/cpanel/base/hostguardian/backup"

# Version
VERSION="1.0.0"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo -e "${2:-$NC}$1${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

error() {
    log "$1" "$RED"
    # Only try to save state if directory exists
    if [ -d "$(dirname "$INSTALL_STATE_FILE")" ]; then
        save_state "ERROR"
    fi
    if [ "$2" != "no_exit" ]; then
        exit 1
    fi
}

save_state() {
    # Ensure directory exists before saving state
    local state_dir="$(dirname "$INSTALL_STATE_FILE")"
    if [ ! -d "$state_dir" ]; then
        mkdir -p "$state_dir"
    fi
    echo "$1" > "$INSTALL_STATE_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" >> "$INSTALL_STATE_FILE"
    chmod 600 "$INSTALL_STATE_FILE"
}

load_state() {
    if [ -f "$INSTALL_STATE_FILE" ]; then
        cat "$INSTALL_STATE_FILE"
    else
        echo "NEW"
    fi
}

backup_existing() {
    if [ -d "/usr/local/cpanel/base/hostguardian" ]; then
        local backup_time=$(date '+%Y%m%d_%H%M%S')
        mkdir -p "$BACKUP_DIR"
        tar czf "$BACKUP_DIR/backup_$backup_time.tar.gz" -C /usr/local/cpanel/base hostguardian
        log "Created backup at $BACKUP_DIR/backup_$backup_time.tar.gz" "$GREEN"
    fi
}

restore_backup() {
    local latest_backup=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
        log "Restoring from backup: $latest_backup" "$YELLOW"
        tar xzf "$latest_backup" -C /usr/local/cpanel/base
        return 0
    fi
    return 1
}

check_dependencies() {
    local missing_deps=()
    
    # Check system commands
    for cmd in mysql wget tar gcc make; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    # Check Perl modules
    for module in DBI DBD::mysql JSON::XS Time::Piece Config::Simple; do
        if ! perl -M$module -e1 2>/dev/null; then
            missing_deps+=($module)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "Missing dependencies: ${missing_deps[*]}" "$YELLOW"
        return 1
    fi
    return 0
}

install_dependencies() {
    log "Installing dependencies..." "$YELLOW"
    if [ -f /etc/redhat-release ]; then
        retry 3 yum clean all
        retry 3 yum update -y
        retry 3 yum install -y gcc make mysql-devel perl-DBI perl-DBD-MySQL perl-JSON-XS perl-Time-Piece perl-Config-Simple
    else
        retry 3 apt-get update
        retry 3 apt-get install -y gcc make libmysqlclient-dev libdbi-perl libdbd-mysql-perl libjson-xs-perl libtime-piece-perl libconfig-simple-perl
    fi
}

# Function to retry commands
retry() {
    local retries=$1
    shift
    local count=0
    until "$@"; do
        exit=$?
        count=$((count + 1))
        if [ $count -lt $retries ]; then
            log "Command failed. Attempt $count/$retries. Retrying..." "$YELLOW"
            sleep 5
        else
            error "The command has failed after $retries attempts."
            return 1
        fi
    done
    return 0
}

# Main installation steps
main() {
    # Create base directories first
    log "Creating base directories..." "$YELLOW"
    mkdir -p /usr/local/cpanel/base/hostguardian
    mkdir -p /var/log/hostguardian
    
    # Now we can safely save state
    local current_state=$(load_state)
    
    case $current_state in
        "NEW"|"ERROR")
            log "Starting fresh installation..." "$GREEN"
            save_state "INSTALLING"
            backup_existing
            ;;
        "COMPLETED")
            log "Installation already completed. Use --force to reinstall." "$YELLOW"
            exit 0
            ;;
    esac
    
    # Check dependencies
    if ! check_dependencies; then
        log "Installing missing dependencies..." "$YELLOW"
        install_dependencies
    fi
    
    # Create remaining directories
    log "Creating additional directories..." "$YELLOW"
    mkdir -p /usr/local/cpanel/Cpanel/HostGuardian
    mkdir -p /usr/local/cpanel/whm/docroot/cgi
    mkdir -p /usr/local/cpanel/base/frontend/paper_lantern/hostguardian
    mkdir -p /usr/local/cpanel/base/hostguardian/quarantine
    
    # Set permissions
    chmod 755 /usr/local/cpanel/base/hostguardian
    chmod 755 /usr/local/cpanel/base/hostguardian/quarantine
    chmod 755 /var/log/hostguardian
    
    # Database setup with retry
    local db_setup_success=false
    for i in {1..3}; do
        if setup_database; then
            db_setup_success=true
            break
        fi
        log "Database setup attempt $i failed. Retrying..." "$YELLOW"
        sleep 5
    done
    
    if [ "$db_setup_success" = false ]; then
        error "Database setup failed after 3 attempts"
    fi
    
    # Copy files and set permissions
    copy_files || error "Failed to copy files"
    
    # Register hooks
    register_hooks || error "Failed to register hooks"
    
    # Verify installation
    if verify_installation; then
        save_state "COMPLETED"
        log "Installation completed successfully!" "$GREEN"
    else
        error "Installation verification failed"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            if [ -f "$INSTALL_STATE_FILE" ]; then
                rm -f "$INSTALL_STATE_FILE"
            fi
            ;;
        --test-mode)
            export TEST_MODE=1
            ;;
        --help)
            echo "Usage: $0 [--force] [--test-mode] [--help]"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
    shift
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root"
fi

# Check if running on a cPanel server
if [ ! -d "/usr/local/cpanel" ]; then
    error "This script must be run on a cPanel server"
fi

log "Starting HostGuardian installation..." "$GREEN"

# Function to retry commands
retry() {
    local retries=$1
    shift
    local count=0
    until "$@"; do
        exit=$?
        count=$((count + 1))
        if [ $count -lt $retries ]; then
            log "Command failed. Attempt $count/$retries. Retrying..." "$YELLOW"
            sleep 5
        else
            error "The command has failed after $retries attempts."
        fi
    done
    return 0
}

# Create necessary directories
log "Creating directories..." "$YELLOW"
mkdir -p /usr/local/cpanel/base/hostguardian
mkdir -p /usr/local/cpanel/Cpanel/HostGuardian
mkdir -p /usr/local/cpanel/whm/docroot/cgi
mkdir -p /usr/local/cpanel/base/frontend/paper_lantern/hostguardian
mkdir -p /usr/local/cpanel/base/hostguardian/quarantine
mkdir -p /var/log/hostguardian

# Set correct permissions
chmod 755 /usr/local/cpanel/base/hostguardian
chmod 755 /usr/local/cpanel/base/hostguardian/quarantine
chmod 755 /var/log/hostguardian

# Install required system packages
log "Installing system dependencies..." "$YELLOW"
if [ -f /etc/redhat-release ]; then
    # CentOS/RHEL
    retry 3 yum clean all
    retry 3 yum update -y
    retry 3 yum install -y gcc make mysql-devel perl-DBI perl-DBD-MySQL perl-JSON-XS perl-Time-Piece perl-Config-Simple
else
    # Debian/Ubuntu
    retry 3 apt-get update
    retry 3 apt-get install -y gcc make libmysqlclient-dev libdbi-perl libdbd-mysql-perl libjson-xs-perl libtime-piece-perl libconfig-simple-perl
fi

# Install Perl dependencies
log "Installing Perl dependencies..." "$YELLOW"
retry 3 /usr/local/cpanel/3rdparty/bin/perl -MCPAN -e 'CPAN::Shell->notest("install", "DBI")'
retry 3 /usr/local/cpanel/3rdparty/bin/perl -MCPAN -e 'CPAN::Shell->notest("install", "DBD::mysql@4.050")'
retry 3 /usr/local/cpanel/3rdparty/bin/perl -MCPAN -e 'CPAN::Shell->notest("install", "JSON::XS")'
retry 3 /usr/local/cpanel/3rdparty/bin/perl -MCPAN -e 'CPAN::Shell->notest("install", "Time::Piece")'
retry 3 /usr/local/cpanel/3rdparty/bin/perl -MCPAN -e 'CPAN::Shell->notest("install", "Config::Simple")'

# Copy files
log "Installing HostGuardian files..." "$YELLOW"

# Copy CGI scripts
cp -f whm/hostguardian.cgi /usr/local/cpanel/whm/docroot/cgi/
cp -f cpanel/hostguardian.cgi /usr/local/cpanel/base/frontend/paper_lantern/hostguardian/

# Copy Perl modules
cp -rf Cpanel/HostGuardian/* /usr/local/cpanel/Cpanel/HostGuardian/

# Set correct permissions
log "Setting permissions..." "$YELLOW"
chmod 755 /usr/local/cpanel/whm/docroot/cgi/hostguardian.cgi
chmod 755 /usr/local/cpanel/base/frontend/paper_lantern/hostguardian/hostguardian.cgi
chmod 755 /usr/local/cpanel/Cpanel/HostGuardian/*
chmod 644 /usr/local/cpanel/Cpanel/HostGuardian/Hooks.pm

# Generate random password for database
DB_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

# Create configuration file
log "Creating configuration..." "$YELLOW"
cat > /usr/local/cpanel/base/hostguardian/config.ini << EOL
[database]
host = localhost
name = hostguardian
user = hostguardian
pass = ${DB_PASS}

[scan]
quick_scan_max_files = 1000
full_scan_threads = 4
scan_timeout = 3600

[quarantine]
path = /usr/local/cpanel/base/hostguardian/quarantine
retention_days = 30

[update]
signature_url = https://hostguardian.net/signatures/latest
auto_update = 1
update_interval = 86400

[logging]
level = info
file = /var/log/hostguardian/hostguardian.log
max_size = 10M
max_files = 5

[security]
min_scan_interval = 300
max_concurrent_scans = 3
blocked_paths = /tmp,/dev,/proc,/sys
allowed_file_types = php,pl,cgi,py,js,sh,bash,html,htm,tpl

[notification]
email_alerts = 1
email_level = high
webhook_url = 
discord_webhook = 
EOL

chmod 600 /usr/local/cpanel/base/hostguardian/config.ini

# Set up database
log "Setting up database..." "$YELLOW"
retry 3 mysql -e "CREATE DATABASE IF NOT EXISTS hostguardian CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
retry 3 mysql -e "CREATE USER IF NOT EXISTS 'hostguardian'@'localhost' IDENTIFIED BY '${DB_PASS}';"
retry 3 mysql -e "GRANT ALL PRIVILEGES ON hostguardian.* TO 'hostguardian'@'localhost';"
retry 3 mysql -e "FLUSH PRIVILEGES;"

# Import schema
log "Importing database schema..." "$YELLOW"
retry 3 mysql hostguardian < schema.sql

# Register hooks
log "Registering cPanel hooks..." "$YELLOW"
retry 3 /usr/local/cpanel/bin/manage_hooks delete module HostGuardian::Hooks
retry 3 /usr/local/cpanel/bin/manage_hooks add module HostGuardian::Hooks

# Verify installation
log "Verifying installation..." "$YELLOW"

# Check Perl modules
PERL_MODS=("DBI" "DBD::mysql" "JSON::XS" "Time::Piece" "Config::Simple")
for mod in "${PERL_MODS[@]}"; do
    if ! /usr/local/cpanel/3rdparty/bin/perl -M"$mod" -e 1 &>/dev/null; then
        error "Perl module $mod is not installed correctly"
    fi
done

# Check files
FILES=(
    "/usr/local/cpanel/whm/docroot/cgi/hostguardian.cgi"
    "/usr/local/cpanel/base/frontend/paper_lantern/hostguardian/hostguardian.cgi"
    "/usr/local/cpanel/Cpanel/HostGuardian/Hooks.pm"
    "/usr/local/cpanel/base/hostguardian/config.ini"
)
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        error "Required file $file is missing"
    fi
done

# Check database connection
if ! mysql -u hostguardian -p"${DB_PASS}" hostguardian -e "SELECT 1" &>/dev/null; then
    error "Cannot connect to database"
fi

# Create symlinks for paper_lantern theme
ln -sf /usr/local/cpanel/base/frontend/paper_lantern/hostguardian /usr/local/cpanel/base/frontend/jupiter/hostguardian

# Register with cPanel
if [ -f "/usr/local/cpanel/scripts/install_plugin" ]; then
    retry 3 /usr/local/cpanel/scripts/install_plugin hostguardian.tar.gz --theme=paper_lantern
fi

log "Installation completed successfully!" "$GREEN"
log "Configuration file: /usr/local/cpanel/base/hostguardian/config.ini" "$GREEN"
log "Log file: /var/log/hostguardian/hostguardian.log" "$GREEN"
log "Database password has been automatically generated and configured" "$GREEN"

# Save installation details
cat > /usr/local/cpanel/base/hostguardian/install_info.txt << EOL
Installation Date: $(date)
Version: 1.0.0
Database User: hostguardian
Database Name: hostguardian
Log File: /var/log/hostguardian/hostguardian.log
Config File: /usr/local/cpanel/base/hostguardian/config.ini
EOL

chmod 600 /usr/local/cpanel/base/hostguardian/install_info.txt

log "To verify the installation, visit:" "$GREEN"
log "WHM: https://your-server:2087/cgi/hostguardian/index.cgi" "$GREEN"
log "cPanel: https://your-server:2083/hostguardian/index.cgi" "$GREEN"

copy_files() {
    log "Installing HostGuardian files..." "$YELLOW"
    
    # Create necessary directories if they don't exist
    mkdir -p /usr/local/cpanel/Cpanel/HostGuardian
    mkdir -p /usr/local/cpanel/whm/docroot/cgi
    mkdir -p /usr/local/cpanel/base/frontend/paper_lantern/hostguardian
    mkdir -p /usr/local/cpanel/base/hostguardian/quarantine
    
    # Copy Hooks module
    if [ -f "hooks.pl" ]; then
        cp -f hooks.pl /usr/local/cpanel/Cpanel/HostGuardian/Hooks.pm
    elif [ -f "Cpanel/HostGuardian/Hooks.pm" ]; then
        cp -f Cpanel/HostGuardian/Hooks.pm /usr/local/cpanel/Cpanel/HostGuardian/
    else
        error "Hooks module not found"
    fi
    
    # Copy CGI scripts
    if [ -d "whm" ]; then
        cp -f whm/hostguardian.cgi /usr/local/cpanel/whm/docroot/cgi/
    fi
    
    if [ -d "cpanel" ]; then
        cp -f cpanel/hostguardian.cgi /usr/local/cpanel/base/frontend/paper_lantern/hostguardian/
    fi
    
    # Copy configuration
    if [ -f "config.ini" ]; then
        cp -f config.ini /usr/local/cpanel/base/hostguardian/
    fi
    
    # Set permissions
    chmod 755 /usr/local/cpanel/whm/docroot/cgi/hostguardian.cgi
    chmod 755 /usr/local/cpanel/base/frontend/paper_lantern/hostguardian/hostguardian.cgi
    chmod 755 /usr/local/cpanel/Cpanel/HostGuardian/Hooks.pm
    chmod 600 /usr/local/cpanel/base/hostguardian/config.ini
    
    return 0
} 