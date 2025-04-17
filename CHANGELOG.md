# Changelog

All notable changes to HostGuardian will be documented in this file.

## [1.0.0] - 2024-03-20

### Added
- Real-time file scanning with multi-threaded processing (up to 4 threads)
- Modern WHM interface with Bootstrap 5.0 and dynamic AJAX updates
- Responsive cPanel interface compatible with Paper Lantern and Jupiter themes
- MySQL/MariaDB database integration with automatic failover
- Quarantine system with configurable retention (default: 30 days)
- Email notifications with HTML and plain text templates
- Discord/Webhook integration with customizable alerts
- Auto-update system for virus signatures (24-hour intervals)
- Scheduled scanning with cron integration
- cPanel hooks integration for backup, restore, suspend operations
- File integrity monitoring with SHA-256 hashing
- Detailed logging system with rotation (max 10MB per file)
- User-specific settings stored in MySQL
- Real-time threat statistics and reporting dashboard

### Security
- Secure database password generation using OpenSSL
- File permissions hardened to 600/644/755
- Quarantine isolation with separate user directories
- Comprehensive error handling and logging
- Prepared statements for all database queries
- XSS protection with HTML escaping
- CSRF token implementation
- Input validation for all user parameters

### Dependencies
- Updated DBD::mysql to version 4.050
- Added JSON::XS for improved performance
- Added Time::Piece for timestamp handling
- Added Config::Simple for configuration management
- Required Perl 5.10+ compatibility
- MySQL 5.7+ or MariaDB 10.3+ required

### Fixed
- DBD::mysql compatibility issues with newer MySQL versions
- Config parsing errors with special characters
- Database connection handling with automatic retry
- Hook registration reliability during installation
- Installation script interruption recovery
- File permission issues in cPanel's restricted environment
- Log rotation for large log files
- Theme compatibility with Jupiter and Paper Lantern

## [0.9.0] - 2024-03-15

### Added
- Beta testing release
- Basic file scanning engine
- Simple WHM/cPanel interface
- MySQL database schema
- Installation script with dependency checks

### Fixed
- Initial database connection issues
- Installation script dependency resolution
- Permission problems with cPanel directories
- Basic error handling implementation

## [0.8.0] - 2024-03-10

### Added
- Alpha release for internal testing
- Core scanning functionality
- Basic UI implementation
- Initial installation process

### Known Issues
- Installation process interruptions
- Database connection stability issues
- Hook registration reliability
- File permission problems in restricted environments

### Migration Notes
- Requires manual database backup before upgrading from alpha
- Configuration files need to be recreated after upgrade
- Hooks must be re-registered after installation 