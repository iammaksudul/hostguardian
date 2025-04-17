-- HostGuardian Database Schema

-- System settings table
CREATE TABLE IF NOT EXISTS hg_system_settings (
    name VARCHAR(64) PRIMARY KEY,
    value TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- User settings table
CREATE TABLE IF NOT EXISTS hg_user_settings (
    user_id VARCHAR(64),
    setting_name VARCHAR(64),
    setting_value TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, setting_name)
);

-- Scans table
CREATE TABLE IF NOT EXISTS hg_scans (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(64),
    scan_type VARCHAR(32),
    status VARCHAR(16),
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP NULL,
    total_files INT DEFAULT 0,
    scanned_files INT DEFAULT 0,
    threats_found INT DEFAULT 0,
    INDEX idx_user_status (user_id, status)
);

-- Threats table
CREATE TABLE IF NOT EXISTS hg_threats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    scan_id BIGINT,
    file_path VARCHAR(512),
    threat_type VARCHAR(64),
    status VARCHAR(16),
    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    details TEXT,
    FOREIGN KEY (scan_id) REFERENCES hg_scans(id),
    INDEX idx_scan_status (scan_id, status)
);

-- Schedules table
CREATE TABLE IF NOT EXISTS hg_schedules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(64),
    schedule_type VARCHAR(32),
    path VARCHAR(512),
    frequency VARCHAR(32),
    last_run TIMESTAMP NULL,
    next_run TIMESTAMP NULL,
    status VARCHAR(16),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_status (user_id, status)
);

-- Protected paths table
CREATE TABLE IF NOT EXISTS hg_protected_paths (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(64),
    path VARCHAR(512),
    active BOOLEAN DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_active (user_id, active)
);

-- Insert default system settings
INSERT INTO hg_system_settings (name, value) VALUES
('install_date', CURRENT_DATE()),
('version', '1.0.0'),
('license_type', 'trial'),
('trial_start_date', CURRENT_DATE()); 