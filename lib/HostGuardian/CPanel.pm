=head1 NAME

HostGuardian::CPanel - cPanel interface for HostGuardian virus scanner

=head1 SYNOPSIS

    use HostGuardian::CPanel;
    HostGuardian::CPanel->display_page('index');

=head1 DESCRIPTION

This module provides the cPanel user interface for the HostGuardian virus scanner.
It handles user-level scanning operations, threat management, and settings.

=head1 AUTHOR

Kh Maksudul Alam (@iammaksudul)
https://github.com/iammaksudul

HostGuardian Development Team

=head1 LICENSE

Copyright (c) 2024 HostGuardian

This is proprietary software.

=cut

package HostGuardian::CPanel;

use strict;
use warnings;
use JSON::XS;
use CGI;
use Cpanel::Template;
use Cpanel::CPDATA ();
use Cpanel::Locale ();
use Cpanel::Themes ();
use Cpanel::Logger ();
use Cpanel::Version ();
use Time::Piece;

our $VERSION = '1.0.0';

# Check trial status
sub check_trial_status {
    my ($class) = @_;
    my $dbh = HostGuardian::DB->connect();
    my $logger = Cpanel::Logger->init("HostGuardian");
    
    eval {
        # Get installation date
        my $sth = $dbh->prepare("SELECT value FROM hg_system_settings WHERE name = 'install_date'");
        $sth->execute();
        my ($install_date) = $sth->fetchrow_array();
        
        unless ($install_date) {
            # First time installation
            $install_date = Time::Piece->new->strftime('%Y-%m-%d');
            $dbh->do(
                "INSERT INTO hg_system_settings (name, value) VALUES (?, ?)",
                undef,
                'install_date',
                $install_date
            );
        }
        
        # Calculate days since installation
        my $t = Time::Piece->strptime($install_date, '%Y-%m-%d');
        my $now = Time::Piece->new;
        my $days_elapsed = int(($now - $t) / (24*60*60));
        
        # Check if trial has expired
        if ($days_elapsed > 30) {
            my $license_key = _get_license_key();
            unless ($license_key) {
                return {
                    status => 'expired',
                    days_elapsed => $days_elapsed,
                    purchase_url => 'https://hostguardian.maksudulalam.com'
                };
            }
        }
        
        return {
            status => 'active',
            days_remaining => 30 - $days_elapsed,
            days_elapsed => $days_elapsed
        };
    };
    if ($@) {
        $logger->error("Failed to check trial status: $@");
        return { status => 'error', message => $@ };
    }
}

# Get license key if exists
sub _get_license_key {
    my $dbh = HostGuardian::DB->connect();
    my $sth = $dbh->prepare("SELECT value FROM hg_system_settings WHERE name = 'license_key'");
    $sth->execute();
    my ($license_key) = $sth->fetchrow_array();
    return $license_key;
}

# cPanel page handler
sub display_page {
    my ($class, $page) = @_;
    my $cgi = CGI->new;
    
    # Check trial status
    my $trial_status = $class->check_trial_status();
    if ($trial_status->{status} eq 'expired') {
        # Show trial expired page
        my $template = Cpanel::Template->new();
        my $vars = {
            days_elapsed => $trial_status->{days_elapsed},
            purchase_url => $trial_status->{purchase_url}
        };
        
        my $output = $template->process("hostguardian/cpanel/trial_expired.tmpl", $vars);
        print $cgi->header(-charset => 'utf-8');
        print $output;
        return;
    }

    # Get user data and locale
    my $cpdata = Cpanel::CPDATA::CPDATA();
    my $user = $cpdata->{'USER'};
    my $locale = Cpanel::Locale->get_handle();
    
    # Get theme
    my $theme = Cpanel::Themes::get_theme_for_user($user);
    
    # Initialize logger
    my $logger = Cpanel::Logger->init("HostGuardian");
    
    my $template = Cpanel::Template->new();
    my $vars = {
        theme => $theme,
        locale => $locale,
        stats => _get_user_stats($user),
        scans => _get_user_scans($user),
        settings => _get_user_settings($user),
        version => $VERSION,
        base_url => Cpanel::Template::get_base_url(),
        is_reseller => Cpanel::Resellers::is_reseller($user),
    };
    
    # Load appropriate template
    eval {
        my $output = $template->process("hostguardian/cpanel/$page.tmpl", $vars);
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
    
    my $cpdata = Cpanel::CPDATA::CPDATA();
    my $user = $cpdata->{'USER'};
    my $logger = Cpanel::Logger->init("HostGuardian");
    
    my $response = {success => 0, message => 'Invalid action'};
    
    eval {
        if ($action eq 'start_scan') {
            $response = _handle_start_scan($cgi, $user);
        }
        elsif ($action eq 'get_scan_status') {
            $response = _handle_get_scan_status($cgi, $user);
        }
        elsif ($action eq 'update_settings') {
            $response = _handle_update_user_settings($cgi, $user);
        }
        elsif ($action eq 'manage_threat') {
            $response = _handle_manage_user_threat($cgi, $user);
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

# Get user-specific theme
sub _get_user_theme {
    my $user = shift;
    my $dbh = HostGuardian::DB->connect();
    
    my $sth = $dbh->prepare(
        "SELECT setting_value FROM hg_user_settings 
         WHERE user_id = ? AND setting_name = 'theme'"
    );
    $sth->execute($user);
    my ($theme) = $sth->fetchrow_array();
    
    return $theme || 'light';
}

# Get user statistics
sub _get_user_stats {
    my $user = shift;
    my $stats = {
        total_scans => 0,
        active_threats => 0,
        protected_dirs => 0,
        last_scan_time => undef,
    };
    
    my $dbh = HostGuardian::DB->connect();
    eval {
        # Get total scans
        my $sth = $dbh->prepare(
            "SELECT COUNT(*) FROM hg_scans WHERE user_id = ?"
        );
        $sth->execute($user);
        ($stats->{total_scans}) = $sth->fetchrow_array();
        
        # Get active threats
        $sth = $dbh->prepare(
            "SELECT COUNT(*) FROM hg_threats t 
             JOIN hg_scans s ON t.scan_id = s.id 
             WHERE s.user_id = ? AND t.status = 'detected'"
        );
        $sth->execute($user);
        ($stats->{active_threats}) = $sth->fetchrow_array();
        
        # Get protected directories
        $sth = $dbh->prepare(
            "SELECT COUNT(*) FROM hg_protected_paths 
             WHERE user_id = ? AND active = 1"
        );
        $sth->execute($user);
        ($stats->{protected_dirs}) = $sth->fetchrow_array();
        
        # Get last scan time
        $sth = $dbh->prepare(
            "SELECT MAX(end_time) FROM hg_scans 
             WHERE user_id = ? AND status = 'completed'"
        );
        $sth->execute($user);
        ($stats->{last_scan_time}) = $sth->fetchrow_array();
    };
    if ($@) {
        Cpanel::Logger->warn("Failed to get user stats: $@");
    }
    
    return $stats;
}

# Get user's recent scans
sub _get_user_scans {
    my $user = shift;
    my $dbh = HostGuardian::DB->connect();
    
    my $sth = $dbh->prepare(
        "SELECT s.*, COUNT(t.id) as threat_count 
         FROM hg_scans s 
         LEFT JOIN hg_threats t ON s.id = t.scan_id 
         WHERE s.user_id = ? 
         GROUP BY s.id 
         ORDER BY s.start_time DESC 
         LIMIT 10"
    );
    $sth->execute($user);
    
    my @scans;
    while (my $row = $sth->fetchrow_hashref) {
        push @scans, $row;
    }
    
    return \@scans;
}

# Get user settings
sub _get_user_settings {
    my $user = shift;
    my $dbh = HostGuardian::DB->connect();
    
    my $sth = $dbh->prepare(
        "SELECT setting_name, setting_value 
         FROM hg_user_settings 
         WHERE user_id = ?"
    );
    $sth->execute($user);
    
    my $settings = {};
    while (my ($name, $value) = $sth->fetchrow_array) {
        $settings->{$name} = $value;
    }
    
    return $settings;
}

# Handle user scan initiation
sub _handle_start_scan {
    my ($cgi, $user) = @_;
    my $scan_type = $cgi->param('scan_type') || 'full';
    my $path = $cgi->param('path') || $ENV{'HOME'};
    
    # Validate path is within user's home directory
    unless ($path =~ /^$ENV{'HOME'}/) {
        return {
            success => 0,
            message => Cpanel::Locale->get_handle()->maketext('Invalid path specified')
        };
    }
    
    # Check resource limits
    my $resource_check = Cpanel::ResourceLimits::check_limits($user);
    unless ($resource_check->{success}) {
        return {
            success => 0,
            message => $resource_check->{message}
        };
    }
    
    my $scanner = HostGuardian::Scanner->new(
        scan_type => $scan_type,
        user_id => $user,
        enable_ml => 1,
    );
    
    my $scan_id = $scanner->scan_path($path);
    
    return {
        success => 1,
        scan_id => $scan_id,
        message => Cpanel::Locale->get_handle()->maketext('Scan initiated successfully')
    };
}

# Handle user threat management
sub _handle_manage_user_threat {
    my ($cgi, $user) = @_;
    my $threat_id = $cgi->param('threat_id');
    my $action = $cgi->param('action');
    
    return {success => 0, message => 'Invalid parameters'}
        unless $threat_id && $action;
    
    # Verify threat belongs to user
    my $dbh = HostGuardian::DB->connect();
    my $sth = $dbh->prepare(
        "SELECT t.* FROM hg_threats t 
         JOIN hg_scans s ON t.scan_id = s.id 
         WHERE t.id = ? AND s.user_id = ?"
    );
    $sth->execute($threat_id, $user);
    my $threat = $sth->fetchrow_hashref;
    
    return {success => 0, message => 'Threat not found'}
        unless $threat;
    
    my $handler = HostGuardian::Threat->new(
        id => $threat_id,
        dbh => $dbh
    );
    
    my $result = $handler->handle_action($action);
    
    return {
        success => $result->{success},
        message => $result->{message}
    };
}

# Update user settings
sub _handle_update_user_settings {
    my ($cgi, $user) = @_;
    my $settings = decode_json($cgi->param('settings'));
    
    my $dbh = HostGuardian::DB->connect();
    my $success = 1;
    my $message = 'Settings updated successfully';
    
    eval {
        $dbh->begin_work;
        
        foreach my $key (keys %$settings) {
            my $sth = $dbh->prepare(
                "INSERT INTO hg_user_settings 
                 (user_id, setting_name, setting_value) 
                 VALUES (?, ?, ?) 
                 ON DUPLICATE KEY UPDATE setting_value = ?"
            );
            $sth->execute($user, $key, $settings->{$key}, $settings->{$key});
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