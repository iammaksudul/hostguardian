=head1 NAME

HostGuardian::WHM - WHM interface for HostGuardian virus scanner

=head1 SYNOPSIS

    use HostGuardian::WHM;
    HostGuardian::WHM->display_page('index');

=head1 DESCRIPTION

This module provides the WHM (WebHost Manager) interface for the HostGuardian virus scanner.
It handles system-wide configuration, server management, and global threat monitoring.

=head1 AUTHOR

Kh Maksudul Alam (@iammaksudul)
https://github.com/iammaksudul

HostGuardian Development Team

=head1 LICENSE

Copyright (c) 2024 HostGuardian

This is proprietary software.

=cut

package HostGuardian::WHM;

use strict;
use warnings;
use JSON::XS;
use CGI;
use Cpanel::Template;
use Cpanel::Config::LoadWwwAcct ();
use Cpanel::AdminBin::Call ();
use Cpanel::Logger ();
use Cpanel::Locale ();
use Cpanel::Version ();
use Cpanel::AccessIds ();

our $VERSION = '1.0.0';

# WHM page handler
sub display_page {
    my ($class, $page) = @_;
    my $cgi = CGI->new;
    
    # Verify WHM authentication
    return _send_auth_error() unless _check_whm_auth();
    
    # Initialize logger and locale
    my $logger = Cpanel::Logger->init("HostGuardian");
    my $locale = Cpanel::Locale->get_handle();
    
    my $template = Cpanel::Template->new();
    my $vars = {
        theme => _get_theme(),
        locale => $locale,
        stats => _get_system_stats(),
        servers => _get_managed_servers(),
        settings => _get_settings(),
        version => $VERSION,
        cpanel_version => Cpanel::Version::getversion(),
        is_root => Cpanel::AccessIds::is_root(),
    };
    
    # Load appropriate template
    eval {
        my $output = $template->process("hostguardian/whm/$page.tmpl", $vars);
        print $cgi->header(-charset => 'utf-8');
        print $output;
    };
    if ($@) {
        $logger->error("Template processing failed: $@");
        print $cgi->header(-status => '500');
        print $locale->maketext('Template processing failed');
    }
}

# API endpoint handler
sub handle_api {
    my ($class, $action) = @_;
    my $cgi = CGI->new;
    
    # Verify WHM authentication
    return _send_auth_error() unless _check_whm_auth();
    
    my $logger = Cpanel::Logger->init("HostGuardian");
    my $response = {success => 0, message => 'Invalid action'};
    
    eval {
        if ($action eq 'start_scan') {
            $response = _handle_start_scan($cgi);
        }
        elsif ($action eq 'get_scan_status') {
            $response = _handle_get_scan_status($cgi);
        }
        elsif ($action eq 'update_settings') {
            $response = _handle_update_settings($cgi);
        }
        elsif ($action eq 'manage_threat') {
            $response = _handle_manage_threat($cgi);
        }
    };
    if ($@) {
        $logger->error("API error: $@");
        $response = {
            success => 0,
            message => "Internal error occurred",
            error => $@
        };
    }
    
    print $cgi->header(-type => 'application/json', -charset => 'utf-8');
    print encode_json($response);
}

# Authentication check
sub _check_whm_auth {
    my $conf = Cpanel::Config::LoadWwwAcct::loadwwwacct();
    return 0 unless $conf;
    
    my $session = Cpanel::AdminBin::Call::verify_session();
    return 0 unless $session;
    
    # Check if user has required ACLs
    my $acls = Cpanel::AccessIds::get_user_acls();
    return 0 unless $acls->{hostguardian};
    
    return 1;
}

# Send authentication error
sub _send_auth_error {
    my $cgi = CGI->new;
    my $locale = Cpanel::Locale->get_handle();
    
    print $cgi->header(-status => '403');
    print $locale->maketext('Access Denied');
}

# Get system statistics with error handling
sub _get_system_stats {
    my $stats = {
        total_scans => 0,
        active_threats => 0,
        protected_accounts => 0,
        last_scan_time => undef,
    };
    
    my $dbh = HostGuardian::DB->connect();
    my $logger = Cpanel::Logger->init("HostGuardian");
    
    eval {
        # Get total scans
        my $sth = $dbh->prepare("SELECT COUNT(*) FROM hg_scans");
        $sth->execute();
        ($stats->{total_scans}) = $sth->fetchrow_array();
        
        # Get active threats
        $sth = $dbh->prepare("SELECT COUNT(*) FROM hg_threats WHERE status = 'detected'");
        $sth->execute();
        ($stats->{active_threats}) = $sth->fetchrow_array();
        
        # Get protected accounts
        $sth = $dbh->prepare("SELECT COUNT(DISTINCT user_id) FROM hg_schedules WHERE status = 'active'");
        $sth->execute();
        ($stats->{protected_accounts}) = $sth->fetchrow_array();
        
        # Get last scan time
        $sth = $dbh->prepare("SELECT MAX(end_time) FROM hg_scans WHERE status = 'completed'");
        $sth->execute();
        ($stats->{last_scan_time}) = $sth->fetchrow_array();
    };
    if ($@) {
        $logger->error("Failed to get system stats: $@");
    }
    
    return $stats;
}

# Handle scan initiation with resource checks
sub _handle_start_scan {
    my $cgi = shift;
    my $scan_type = $cgi->param('scan_type') || 'full';
    my $path = $cgi->param('path') || '/';
    
    # Check system resources
    my $resources = Cpanel::SystemInfo::get_system_info();
    if ($resources->{loadavg} > 5 || $resources->{memory_free} < 512_000) {
        return {
            success => 0,
            message => Cpanel::Locale->get_handle()->maketext('System resources too low for scan')
        };
    }
    
    my $scanner = HostGuardian::Scanner->new(
        scan_type => $scan_type,
        user_id => 0, # Root/WHM user
        enable_ml => 1,
    );
    
    my $scan_id = $scanner->scan_path($path);
    
    # Log scan initiation
    Cpanel::Logger->info("WHM scan initiated: type=$scan_type, path=$path, scan_id=$scan_id");
    
    return {
        success => 1,
        scan_id => $scan_id,
        message => Cpanel::Locale->get_handle()->maketext('Scan initiated successfully')
    };
}

# Handle threat management
sub _handle_manage_threat {
    my $cgi = shift;
    my $threat_id = $cgi->param('threat_id');
    my $action = $cgi->param('action'); # quarantine, delete, whitelist
    
    return {success => 0, message => 'Invalid parameters'}
        unless $threat_id && $action;
    
    my $dbh = HostGuardian::DB->connect();
    my $threat = HostGuardian::Threat->new(
        id => $threat_id,
        dbh => $dbh
    );
    
    my $result = $threat->handle_action($action);
    
    return {
        success => $result->{success},
        message => $result->{message}
    };
}

# Get theme settings
sub _get_theme {
    my $dbh = HostGuardian::DB->connect();
    my $sth = $dbh->prepare("SELECT setting_value FROM hg_settings WHERE setting_name = 'theme'");
    $sth->execute();
    my ($theme) = $sth->fetchrow_array();
    return $theme || 'light';
}

# Get managed servers for multi-server setup
sub _get_managed_servers {
    my $dbh = HostGuardian::DB->connect();
    my $sth = $dbh->prepare("SELECT * FROM hg_managed_servers WHERE active = 1");
    $sth->execute();
    
    my @servers;
    while (my $row = $sth->fetchrow_hashref) {
        push @servers, $row;
    }
    
    return \@servers;
}

# Get plugin settings
sub _get_settings {
    my $dbh = HostGuardian::DB->connect();
    my $sth = $dbh->prepare("SELECT setting_name, setting_value FROM hg_settings");
    $sth->execute();
    
    my $settings = {};
    while (my ($name, $value) = $sth->fetchrow_array) {
        $settings->{$name} = $value;
    }
    
    return $settings;
}

# Update plugin settings
sub _handle_update_settings {
    my $cgi = shift;
    my $settings = decode_json($cgi->param('settings'));
    
    my $dbh = HostGuardian::DB->connect();
    my $success = 1;
    my $message = 'Settings updated successfully';
    
    eval {
        $dbh->begin_work;
        
        foreach my $key (keys %$settings) {
            my $sth = $dbh->prepare(
                "INSERT INTO hg_settings (setting_name, setting_value) 
                 VALUES (?, ?) 
                 ON DUPLICATE KEY UPDATE setting_value = ?"
            );
            $sth->execute($key, $settings->{$key}, $settings->{$key});
        }
        
        $dbh->commit;
    };
    
    if ($@) {
        $dbh->rollback;
        $success = 0;
        $message = "Failed to update settings: $@";
    }
    
    return {
        success => $success,
        message => $message
    };
}

1; 