#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use warnings;
use CGI;
use JSON::XS;
use Cpanel::Template;
use Cpanel::API::Branding ();
use Cpanel::CPDATA ();

# Initialize
my $cgi = CGI->new;
my $cpdata = Cpanel::CPDATA::CPDATA();
my $username = $cpdata->{'USER'};
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
            $response = get_user_stats($username);
        }
        elsif ($action eq 'start_scan') {
            my $scan_type = $cgi->param('scan_type') || 'quick';
            $response = start_scan($username, $scan_type);
        }
        elsif ($action eq 'stop_scan') {
            my $scan_id = $cgi->param('scan_id');
            $response = stop_scan($scan_id);
        }
        elsif ($action eq 'get_threats') {
            $response = get_user_threats($username);
        }
        elsif ($action eq 'quarantine') {
            my $threat_id = $cgi->param('threat_id');
            $response = quarantine_threat($threat_id);
        }
        elsif ($action eq 'restore') {
            my $threat_id = $cgi->param('threat_id');
            $response = restore_threat($threat_id);
        }
        elsif ($action eq 'delete') {
            my $threat_id = $cgi->param('threat_id');
            $response = delete_threat($threat_id);
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
print Cpanel::Template::process_template(
    'stdheader',
    {
        title => 'HostGuardian Virus Scanner',
        include_legacy_stylesheets => 0,
        include_legacy_scripts => 0,
        include_cjt => 0,
        stylesheets => ['hostguardian.css'],
    }
);

my $template = <<'EOT';
<div class="body-content">
    <div class="section">
        <h2>Account Security Status</h2>
        <div id="security-status">Loading...</div>
    </div>
    
    <div class="section">
        <h2>Scan Your Files</h2>
        <div class="scan-options">
            <button id="quick-scan" class="btn btn-primary">
                <i class="fa fa-bolt"></i> Quick Scan
            </button>
            <button id="full-scan" class="btn btn-secondary">
                <i class="fa fa-shield"></i> Full Scan
            </button>
        </div>
        <div id="scan-progress" style="display: none;">
            <h3>Scan in Progress</h3>
            <div class="progress-container">
                <div class="progress-bar">
                    <div class="progress-fill"></div>
                </div>
                <div class="progress-text">0%</div>
            </div>
            <button id="stop-scan" class="btn btn-danger">
                <i class="fa fa-stop"></i> Stop Scan
            </button>
        </div>
    </div>
    
    <div class="section">
        <h2>Detected Threats</h2>
        <div class="threats-tabs">
            <button class="tab-btn active" data-tab="active">Active Threats</button>
            <button class="tab-btn" data-tab="quarantine">Quarantine</button>
            <button class="tab-btn" data-tab="history">History</button>
        </div>
        <div id="threats-content">Loading...</div>
    </div>
    
    <div class="section">
        <h2>Scan History</h2>
        <div id="scan-history">Loading...</div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Initialize the interface
    loadSecurityStatus();
    loadThreats();
    loadScanHistory();
    
    // Set up scan buttons
    document.getElementById('quick-scan').addEventListener('click', () => startScan('quick'));
    document.getElementById('full-scan').addEventListener('click', () => startScan('full'));
    document.getElementById('stop-scan').addEventListener('click', stopScan);
    
    // Set up threat action handlers
    document.addEventListener('click', function(e) {
        if (e.target.classList.contains('quarantine-btn')) {
            quarantineThreat(e.target.dataset.id);
        }
        else if (e.target.classList.contains('restore-btn')) {
            restoreThreat(e.target.dataset.id);
        }
        else if (e.target.classList.contains('delete-btn')) {
            deleteThreat(e.target.dataset.id);
        }
    });
    
    // Set up tab switching
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', function() {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            loadThreats(this.dataset.tab);
        });
    });
    
    // Set up auto-refresh
    setInterval(loadSecurityStatus, 30000);
    setInterval(() => {
        if (document.querySelector('.tab-btn.active')) {
            loadThreats(document.querySelector('.tab-btn.active').dataset.tab);
        }
    }, 10000);
});

function loadSecurityStatus() {
    fetch('hostguardian.cgi?action=get_stats')
        .then(response => response.json())
        .then(data => {
            document.getElementById('security-status').innerHTML = formatSecurityStatus(data);
        });
}

function loadThreats(tab = 'active') {
    fetch(`hostguardian.cgi?action=get_threats&type=${tab}`)
        .then(response => response.json())
        .then(data => {
            document.getElementById('threats-content').innerHTML = formatThreats(data, tab);
        });
}

function loadScanHistory() {
    fetch('hostguardian.cgi?action=get_scan_history')
        .then(response => response.json())
        .then(data => {
            document.getElementById('scan-history').innerHTML = formatScanHistory(data);
        });
}

function startScan(type) {
    fetch('hostguardian.cgi?action=start_scan', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: `scan_type=${type}`
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            document.getElementById('scan-progress').style.display = 'block';
            updateProgress(data.scan_id);
        } else {
            alert('Error: ' + data.error);
        }
    });
}

function updateProgress(scanId) {
    fetch(`hostguardian.cgi?action=get_scan_progress&scan_id=${scanId}`)
        .then(response => response.json())
        .then(data => {
            if (data.status === 'running') {
                document.querySelector('.progress-fill').style.width = data.progress + '%';
                document.querySelector('.progress-text').textContent = data.progress + '%';
                setTimeout(() => updateProgress(scanId), 1000);
            } else {
                document.getElementById('scan-progress').style.display = 'none';
                loadSecurityStatus();
                loadThreats();
            }
        });
}

function stopScan() {
    fetch('hostguardian.cgi?action=stop_scan', { method: 'POST' })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                document.getElementById('scan-progress').style.display = 'none';
                loadSecurityStatus();
            } else {
                alert('Error: ' + data.error);
            }
        });
}

function formatSecurityStatus(data) {
    const riskLevel = calculateRiskLevel(data);
    return `
        <div class="security-grid">
            <div class="status-box ${riskLevel.class}">
                <h3>Risk Level</h3>
                <div class="status-value">${riskLevel.label}</div>
            </div>
            <div class="status-box">
                <h3>Last Scan</h3>
                <div class="status-value">${data.last_scan || 'Never'}</div>
            </div>
            <div class="status-box">
                <h3>Active Threats</h3>
                <div class="status-value">${data.active_threats}</div>
            </div>
            <div class="status-box">
                <h3>Files Scanned</h3>
                <div class="status-value">${data.files_scanned}</div>
            </div>
        </div>
    `;
}

function calculateRiskLevel(data) {
    if (data.active_threats > 10) {
        return { label: 'Critical', class: 'risk-critical' };
    }
    if (data.active_threats > 5) {
        return { label: 'High', class: 'risk-high' };
    }
    if (data.active_threats > 0) {
        return { label: 'Medium', class: 'risk-medium' };
    }
    return { label: 'Low', class: 'risk-low' };
}

function formatThreats(data, tab) {
    if (!data.threats.length) {
        return '<p class="no-data">No threats found</p>';
    }
    
    return `
        <table class="table">
            <thead>
                <tr>
                    <th>File</th>
                    <th>Threat</th>
                    <th>Severity</th>
                    <th>Detected</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                ${data.threats.map(threat => `
                    <tr class="severity-${threat.severity}">
                        <td>${threat.file_path}</td>
                        <td>${threat.threat_name}</td>
                        <td>${threat.severity}</td>
                        <td>${threat.detected_at}</td>
                        <td>
                            ${formatThreatActions(threat, tab)}
                        </td>
                    </tr>
                `).join('')}
            </tbody>
        </table>
    `;
}

function formatThreatActions(threat, tab) {
    if (tab === 'active') {
        return `
            <button class="btn btn-warning quarantine-btn" data-id="${threat.id}">
                <i class="fa fa-lock"></i> Quarantine
            </button>
            <button class="btn btn-danger delete-btn" data-id="${threat.id}">
                <i class="fa fa-trash"></i> Delete
            </button>
        `;
    }
    if (tab === 'quarantine') {
        return `
            <button class="btn btn-success restore-btn" data-id="${threat.id}">
                <i class="fa fa-undo"></i> Restore
            </button>
            <button class="btn btn-danger delete-btn" data-id="${threat.id}">
                <i class="fa fa-trash"></i> Delete
            </button>
        `;
    }
    return '';
}

function formatScanHistory(data) {
    if (!data.scans.length) {
        return '<p class="no-data">No scan history available</p>';
    }
    
    return `
        <table class="table">
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Type</th>
                    <th>Duration</th>
                    <th>Files Scanned</th>
                    <th>Threats Found</th>
                </tr>
            </thead>
            <tbody>
                ${data.scans.map(scan => `
                    <tr>
                        <td>${scan.date}</td>
                        <td>${scan.type}</td>
                        <td>${scan.duration}</td>
                        <td>${scan.files_scanned}</td>
                        <td>${scan.threats_found}</td>
                    </tr>
                `).join('')}
            </tbody>
        </table>
    `;
}

function quarantineThreat(id) {
    if (confirm('Are you sure you want to quarantine this file?')) {
        fetch('hostguardian.cgi?action=quarantine', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: `threat_id=${id}`
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                loadThreats();
                loadSecurityStatus();
            } else {
                alert('Error: ' + data.error);
            }
        });
    }
}

function restoreThreat(id) {
    if (confirm('Are you sure you want to restore this file from quarantine?')) {
        fetch('hostguardian.cgi?action=restore', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: `threat_id=${id}`
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                loadThreats();
                loadSecurityStatus();
            } else {
                alert('Error: ' + data.error);
            }
        });
    }
}

function deleteThreat(id) {
    if (confirm('Are you sure you want to permanently delete this file?')) {
        fetch('hostguardian.cgi?action=delete', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: `threat_id=${id}`
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                loadThreats();
                loadSecurityStatus();
            } else {
                alert('Error: ' + data.error);
            }
        });
    }
}
</script>

<style>
.body-content {
    padding: 20px;
    max-width: 1200px;
    margin: 0 auto;
}

.section {
    background: #fff;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    margin-bottom: 30px;
    padding: 20px;
}

.security-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 20px;
    margin-top: 20px;
}

.status-box {
    background: #f8f9fa;
    border-radius: 8px;
    padding: 20px;
    text-align: center;
}

.status-box h3 {
    margin: 0 0 10px;
    font-size: 16px;
    color: #666;
}

.status-value {
    font-size: 24px;
    font-weight: bold;
}

.risk-critical { background: #ffebee; }
.risk-high { background: #fff3e0; }
.risk-medium { background: #fff8e1; }
.risk-low { background: #f1f8e9; }

.scan-options {
    display: flex;
    gap: 20px;
    margin-bottom: 20px;
}

.progress-container {
    margin: 20px 0;
}

.progress-bar {
    background: #e9ecef;
    border-radius: 4px;
    height: 20px;
    overflow: hidden;
    position: relative;
}

.progress-fill {
    background: #007bff;
    height: 100%;
    transition: width 0.3s ease;
    width: 0;
}

.progress-text {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    color: #fff;
    font-weight: bold;
    text-shadow: 0 0 2px rgba(0,0,0,0.5);
}

.threats-tabs {
    display: flex;
    gap: 10px;
    margin-bottom: 20px;
}

.tab-btn {
    background: none;
    border: none;
    padding: 10px 20px;
    cursor: pointer;
    border-radius: 4px;
}

.tab-btn.active {
    background: #007bff;
    color: #fff;
}

.table {
    width: 100%;
    border-collapse: collapse;
}

.table th,
.table td {
    padding: 12px;
    text-align: left;
    border-bottom: 1px solid #dee2e6;
}

.table th {
    background: #f8f9fa;
    font-weight: 600;
}

.severity-critical { background: #ffebee; }
.severity-high { background: #fff3e0; }
.severity-medium { background: #fff8e1; }
.severity-low { background: #f1f8e9; }

.btn {
    padding: 8px 16px;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-weight: 500;
    display: inline-flex;
    align-items: center;
    gap: 8px;
}

.btn i {
    font-size: 14px;
}

.btn-primary {
    background: #007bff;
    color: #fff;
}

.btn-secondary {
    background: #6c757d;
    color: #fff;
}

.btn-warning {
    background: #ffc107;
    color: #000;
}

.btn-danger {
    background: #dc3545;
    color: #fff;
}

.btn-success {
    background: #28a745;
    color: #fff;
}

.no-data {
    text-align: center;
    color: #666;
    font-style: italic;
    padding: 20px;
}

@media (max-width: 768px) {
    .security-grid {
        grid-template-columns: 1fr;
    }
    
    .scan-options {
        flex-direction: column;
    }
    
    .threats-tabs {
        flex-wrap: wrap;
    }
    
    .table {
        display: block;
        overflow-x: auto;
    }
}
</style>
EOT

print $template;
print Cpanel::Template::process_template('stdfooter'); 