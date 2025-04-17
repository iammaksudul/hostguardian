-- HostGuardian Database Schema
-- Copyright (c) 2024 HostGuardian

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Scans table
CREATE TABLE IF NOT EXISTS `scans` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `type` enum('quick','full') NOT NULL DEFAULT 'quick',
  `status` enum('queued','running','paused','completed','stopped','failed') NOT NULL DEFAULT 'queued',
  `progress` int(3) NOT NULL DEFAULT 0,
  `files_scanned` bigint(20) NOT NULL DEFAULT 0,
  `threats_found` int(11) NOT NULL DEFAULT 0,
  `start_time` datetime DEFAULT NULL,
  `end_time` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_username` (`username`),
  KEY `idx_status` (`status`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Threats table
CREATE TABLE IF NOT EXISTS `threats` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `scan_id` bigint(20) NOT NULL,
  `username` varchar(64) NOT NULL,
  `file_path` varchar(1024) NOT NULL,
  `threat_name` varchar(255) NOT NULL,
  `severity` enum('low','medium','high','critical') NOT NULL,
  `status` enum('active','quarantined','restored','deleted') NOT NULL DEFAULT 'active',
  `hash` varchar(64) NOT NULL,
  `detected_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_scan_id` (`scan_id`),
  KEY `idx_username` (`username`),
  KEY `idx_status` (`status`),
  KEY `idx_detected_at` (`detected_at`),
  CONSTRAINT `fk_threats_scan` FOREIGN KEY (`scan_id`) REFERENCES `scans` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Quarantine table
CREATE TABLE IF NOT EXISTS `quarantine` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `threat_id` bigint(20) NOT NULL,
  `username` varchar(64) NOT NULL,
  `original_path` varchar(1024) NOT NULL,
  `quarantine_path` varchar(1024) NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_threat_id` (`threat_id`),
  KEY `idx_username` (`username`),
  CONSTRAINT `fk_quarantine_threat` FOREIGN KEY (`threat_id`) REFERENCES `threats` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Scheduled tasks table
CREATE TABLE IF NOT EXISTS `scheduled_tasks` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `type` enum('quick','full') NOT NULL DEFAULT 'quick',
  `frequency` enum('daily','weekly','monthly') NOT NULL,
  `day_of_week` tinyint(1) DEFAULT NULL,
  `day_of_month` tinyint(2) DEFAULT NULL,
  `hour` tinyint(2) NOT NULL,
  `minute` tinyint(2) NOT NULL,
  `status` enum('enabled','disabled') NOT NULL DEFAULT 'enabled',
  `last_run` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_username` (`username`),
  KEY `idx_status` (`status`),
  KEY `idx_next_run` (`status`,`frequency`,`day_of_week`,`day_of_month`,`hour`,`minute`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Settings table
CREATE TABLE IF NOT EXISTS `settings` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `key` varchar(64) NOT NULL,
  `value` text NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username_key` (`username`,`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Statistics table
CREATE TABLE IF NOT EXISTS `statistics` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `date` date NOT NULL,
  `scans_completed` int(11) NOT NULL DEFAULT 0,
  `files_scanned` bigint(20) NOT NULL DEFAULT 0,
  `threats_detected` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username_date` (`username`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- Insert default settings
INSERT IGNORE INTO settings (setting_key, setting_value, description) VALUES
('scan_thread_limit', '4', 'Maximum number of concurrent scan threads'),
('quick_scan_depth', '3', 'Directory depth for quick scans'),
('quarantine_location', '/usr/local/cpanel/base/hostguardian/quarantine', 'Default quarantine directory'),
('retention_days', '30', 'Number of days to keep scan history'),
('notification_email', 'admin@localhost', 'Email address for notifications'),
('update_frequency', 'daily', 'Frequency of signature updates'); 