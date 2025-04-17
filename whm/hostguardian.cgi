#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use warnings;
use CGI;
use JSON::XS;
use Cpanel::Template;
use Whostmgr::HTMLInterface ();
use Cpanel::Config::LoadWwwAcct ();
use Cpanel::Logger ();

# Initialize
my $cgi = CGI->new;
my $logger = Cpanel::Logger->init();
print $cgi->header();

# Load configuration
my $config = do {
    local $/;
    open my $fh, '<', '/usr/local/cpanel/base/hostguardian/config.ini'
        or die "Cannot open config file: $!";
    <$fh>;
};

# Handle AJAX requests
if ($cgi->param('action')) {
    my $action = $cgi->param('action');
    my $response = {};
    
    eval {
        if ($action eq 'get_stats') {
            $response = get_stats();
        }
        elsif ($action eq 'start_scan') {
            my $username = $cgi->param('username');
            my $scan_type = $cgi->param('scan_type') || 'quick';
            $response = start_scan($username, $scan_type);
        }
        elsif ($action eq 'stop_scan') {
            my $scan_id = $cgi->param('scan_id');
            $response = stop_scan($scan_id);
        }
        elsif ($action eq 'get_threats') {
            my $username = $cgi->param('username');
            $response = get_threats($username);
        }
    };
    if ($@) {
        $response = {
            success => 0,
            error => "Error: $@"
        };
    }
    
    print encode_json($response);
    exit;
}

# Main interface
Whostmgr::HTMLInterface::defheader('HostGuardian Virus Scanner');

my $template = <<'EOT';
<div class="body-content">
    <h2>HostGuardian Virus Scanner</h2>
    
    <div class="section">
        <h3>System Status</h3>
        <div id="system-stats">Loading...</div>
    </div>
    
    <div class="section">
        <h3>Active Scans</h3>
        <div id="active-scans">Loading...</div>
    </div>
    
    <div class="section">
        <h3>Recent Threats</h3>
        <div id="recent-threats">Loading...</div>
    </div>
    
    <div class="section">
        <h3>Start New Scan</h3>
        <form id="scan-form">
            <label>Username:
                <input type="text" name="username" required>
            </label>
            <label>Scan Type:
                <select name="scan_type">
                    <option value="quick">Quick Scan</option>
                    <option value="full">Full Scan</option>
                </select>
            </label>
            <button type="submit">Start Scan</button>
        </form>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Load initial data
    loadStats();
    loadActiveScans();
    loadRecentThreats();
    
    // Set up form submission
    document.getElementById('scan-form').addEventListener('submit', function(e) {
        e.preventDefault();
        startScan(this);
    });
    
    // Set up auto-refresh
    setInterval(loadStats, 30000);
    setInterval(loadActiveScans, 10000);
    setInterval(loadRecentThreats, 60000);
});

function loadStats() {
    fetch('hostguardian.cgi?action=get_stats')
        .then(response => response.json())
        .then(data => {
            document.getElementById('system-stats').innerHTML = formatStats(data);
        });
}

function loadActiveScans() {
    fetch('hostguardian.cgi?action=get_active_scans')
        .then(response => response.json())
        .then(data => {
            document.getElementById('active-scans').innerHTML = formatScans(data);
        });
}

function loadRecentThreats() {
    fetch('hostguardian.cgi?action=get_threats')
        .then(response => response.json())
        .then(data => {
            document.getElementById('recent-threats').innerHTML = formatThreats(data);
        });
}

function startScan(form) {
    const data = new FormData(form);
    fetch('hostguardian.cgi?action=start_scan', {
        method: 'POST',
        body: data
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            alert('Scan started successfully');
            loadActiveScans();
        } else {
            alert('Error: ' + data.error);
        }
    });
}

function formatStats(data) {
    return `
        <div class="stats-grid">
            <div class="stat-box">
                <h4>Total Scans Today</h4>
                <div class="stat-value">${data.scans_today}</div>
            </div>
            <div class="stat-box">
                <h4>Active Scans</h4>
                <div class="stat-value">${data.active_scans}</div>
            </div>
            <div class="stat-box">
                <h4>Threats Detected Today</h4>
                <div class="stat-value">${data.threats_today}</div>
            </div>
            <div class="stat-box">
                <h4>Database Size</h4>
                <div class="stat-value">${data.db_size}</div>
            </div>
        </div>
    `;
}

function formatScans(data) {
    if (!data.scans.length) return '<p>No active scans</p>';
    
    return `
        <table class="table">
            <thead>
                <tr>
                    <th>Username</th>
                    <th>Type</th>
                    <th>Progress</th>
                    <th>Started</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                ${data.scans.map(scan => `
                    <tr>
                        <td>${scan.username}</td>
                        <td>${scan.type}</td>
                        <td>
                            <div class="progress">
                                <div class="progress-bar" style="width: ${scan.progress}%">
                                    ${scan.progress}%
                                </div>
                            </div>
                        </td>
                        <td>${scan.start_time}</td>
                        <td>
                            <button onclick="stopScan(${scan.id})">Stop</button>
                        </td>
                    </tr>
                `).join('')}
            </tbody>
        </table>
    `;
}

function formatThreats(data) {
    if (!data.threats.length) return '<p>No recent threats</p>';
    
    return `
        <table class="table">
            <thead>
                <tr>
                    <th>Username</th>
                    <th>File</th>
                    <th>Threat</th>
                    <th>Severity</th>
                    <th>Status</th>
                    <th>Detected</th>
                </tr>
            </thead>
            <tbody>
                ${data.threats.map(threat => `
                    <tr class="severity-${threat.severity}">
                        <td>${threat.username}</td>
                        <td>${threat.file_path}</td>
                        <td>${threat.threat_name}</td>
                        <td>${threat.severity}</td>
                        <td>${threat.status}</td>
                        <td>${threat.detected_at}</td>
                    </tr>
                `).join('')}
            </tbody>
        </table>
    `;
}
</script>

<style>
.body-content {
    padding: 20px;
}

.section {
    margin-bottom: 30px;
    background: #fff;
    padding: 20px;
    border-radius: 5px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 20px;
    margin-top: 20px;
}

.stat-box {
    background: #f8f9fa;
    padding: 15px;
    border-radius: 5px;
    text-align: center;
}

.stat-value {
    font-size: 24px;
    font-weight: bold;
    color: #007bff;
}

.table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 20px;
}

.table th,
.table td {
    padding: 12px;
    text-align: left;
    border-bottom: 1px solid #dee2e6;
}

.table th {
    background: #f8f9fa;
}

.progress {
    background: #e9ecef;
    border-radius: 3px;
    height: 20px;
    overflow: hidden;
}

.progress-bar {
    background: #007bff;
    color: white;
    text-align: center;
    line-height: 20px;
    transition: width 0.3s ease;
}

.severity-critical { background: #ffebee; }
.severity-high { background: #fff3e0; }
.severity-medium { background: #fff8e1; }
.severity-low { background: #f1f8e9; }

#scan-form {
    display: grid;
    gap: 15px;
    max-width: 400px;
}

#scan-form label {
    display: grid;
    gap: 5px;
}

#scan-form input,
#scan-form select {
    padding: 8px;
    border: 1px solid #ced4da;
    border-radius: 4px;
}

#scan-form button {
    padding: 10px;
    background: #007bff;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
}

#scan-form button:hover {
    background: #0056b3;
}
</style>
EOT

print $template;
Whostmgr::HTMLInterface::footer(); 