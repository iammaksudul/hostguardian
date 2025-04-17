# HostGuardian - cPanel Virus Scanner

HostGuardian is a powerful virus scanning solution integrated with cPanel/WHM, providing real-time protection and scheduled scanning capabilities for your hosting environment.

## Features

- Real-time file scanning
- Scheduled scans (daily, weekly, monthly)
- WHM interface for server-wide management
- cPanel interface for individual user management
- Quarantine system
- Email notifications
- Discord/Webhook notifications
- Detailed scan reports
- Auto-updates for virus signatures
- Integration with cPanel hooks (backup, restore, suspend)

## Requirements

- CentOS 7+ or Ubuntu 18.04+
- cPanel/WHM
- Perl 5.10+
- MySQL/MariaDB
- 512MB+ free RAM
- 1GB+ free disk space

## Installation

1. Clone the repository:
```bash
cd /usr/local/src
git clone https://github.com/iammaksudul/hostguardian.git
cd hostguardian
```

Or download as ZIP:
```bash
cd /usr/local/src
wget https://github.com/iammaksudul/hostguardian/archive/refs/heads/main.zip
unzip main.zip
cd hostguardian-main
```

2. Run the installer:
```bash
chmod +x install.sh
./install.sh
```

The installer will:
- Install required dependencies
- Set up the database
- Configure cPanel hooks
- Create necessary directories
- Set appropriate permissions
- Register the plugin with cPanel

## Configuration

The main configuration file is located at:
```
/usr/local/cpanel/base/hostguardian/config.ini
```

Key configuration options:
- Database settings
- Scan settings (threads, timeouts)
- Quarantine settings
- Update settings
- Notification settings

## Usage

### WHM Interface

Access the WHM interface at:
```
WHM > Plugins > HostGuardian Virus Scanner
```

Features:
- View system-wide scan statistics
- Manage user scans
- View and manage quarantined files
- Configure global settings
- View scan logs

### cPanel Interface

Users can access their interface at:
```
cPanel > Security > HostGuardian Virus Scanner
```

Features:
- Start quick or full scans
- View scan history
- Manage quarantined files
- Configure scan schedules
- View threat reports

## Uninstallation

1. Stop all running scans:
```bash
/usr/local/cpanel/3rdparty/bin/perl /usr/local/cpanel/base/hostguardian/hooks.pl stop_all_scans
```

2. Remove installed files:
```bash
rm -rf /usr/local/src/hostguardian
rm -rf /usr/local/cpanel/base/hostguardian
rm -rf /usr/local/cpanel/Cpanel/HostGuardian
rm -f /usr/local/cpanel/whm/docroot/cgi/hostguardian.cgi
rm -f /usr/local/cpanel/base/frontend/paper_lantern/hostguardian/hostguardian.cgi
```

3. Drop database (optional):
```bash
mysql -e "DROP DATABASE IF EXISTS hostguardian;"
mysql -e "DROP USER IF EXISTS 'hostguardian'@'localhost';"
```

4. Unregister hooks:
```bash
/usr/local/cpanel/bin/manage_hooks delete module HostGuardian::Hooks
```

## Support

For support, please:
- Open an issue on GitHub: https://github.com/iammaksudul/hostguardian/issues
- Check existing issues for solutions
- Review the documentation in the repository

## License

HostGuardian is licensed under the MIT License. See LICENSE file for details.

## Security

To report security issues:
- For critical security issues, please email the maintainer directly
- For non-critical security issues, please create a security advisory on GitHub
- Do not disclose security-related issues publicly until they have been resolved

## Changelog

See CHANGELOG.md for version history. 