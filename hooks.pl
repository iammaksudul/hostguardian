#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use warnings;
use DBI;
use Config::IniFiles;
use Cpanel::Logger ();

my $logger = Cpanel::Logger->init();
my $config = Config::IniFiles->new(-file => "/usr/local/cpanel/base/hostguardian/config.ini");

# Database connection
my $dbh;
eval {
    $dbh = DBI->connect(
        "DBI:mysql:database=" . $config->val('database', 'name') . ";host=" . $config->val('database', 'host'),
        $config->val('database', 'user'),
        $config->val('database', 'password'),
        { RaiseError => 1, AutoCommit => 1 }
    );
};
if ($@) {
    $logger->error("HostGuardian: Database connection failed: $@");
    exit 1;
}

sub pause_scans {
    my ($user) = @_;
    eval {
        $dbh->do(
            "UPDATE scans SET status = 'paused' WHERE user = ? AND status = 'running'",
            undef, $user
        );
        $logger->info("HostGuardian: Paused active scans for user: $user");
    };
    if ($@) {
        $logger->error("HostGuardian: Failed to pause scans: $@");
        return 0;
    }
    return 1;
}

sub resume_scans {
    my ($user) = @_;
    eval {
        $dbh->do(
            "UPDATE scans SET status = 'running' WHERE user = ? AND status = 'paused'",
            undef, $user
        );
        $logger->info("HostGuardian: Resumed paused scans for user: $user");
    };
    if ($@) {
        $logger->error("HostGuardian: Failed to resume scans: $@");
        return 0;
    }
    return 1;
}

sub stop_scans {
    my ($user) = @_;
    eval {
        $dbh->do(
            "UPDATE scans SET status = 'completed' WHERE user = ? AND status IN ('running', 'paused')",
            undef, $user
        );
        $logger->info("HostGuardian: Stopped all scans for user: $user");
    };
    if ($@) {
        $logger->error("HostGuardian: Failed to stop scans: $@");
        return 0;
    }
    return 1;
}

sub disable_scheduled_tasks {
    my ($user) = @_;
    eval {
        $dbh->do(
            "UPDATE scheduled_scans SET enabled = 0 WHERE user = ?",
            undef, $user
        );
        $logger->info("HostGuardian: Disabled scheduled tasks for user: $user");
    };
    if ($@) {
        $logger->error("HostGuardian: Failed to disable scheduled tasks: $@");
        return 0;
    }
    return 1;
}

sub enable_scheduled_tasks {
    my ($user) = @_;
    eval {
        $dbh->do(
            "UPDATE scheduled_scans SET enabled = 1 WHERE user = ?",
            undef, $user
        );
        $logger->info("HostGuardian: Enabled scheduled tasks for user: $user");
    };
    if ($@) {
        $logger->error("HostGuardian: Failed to enable scheduled tasks: $@");
        return 0;
    }
    return 1;
}

sub cleanup_user_data {
    my ($user) = @_;
    eval {
        # Remove quarantined files
        my $quarantine_dir = $config->val('paths', 'quarantine_dir') . "/$user";
        if (-d $quarantine_dir) {
            system("rm", "-rf", $quarantine_dir);
        }

        # Remove database records
        $dbh->do("DELETE FROM scans WHERE user = ?", undef, $user);
        $dbh->do("DELETE FROM scheduled_scans WHERE user = ?", undef, $user);
        $dbh->do("DELETE FROM whitelist WHERE user = ?", undef, $user);
        
        $logger->info("HostGuardian: Cleaned up data for user: $user");
    };
    if ($@) {
        $logger->error("HostGuardian: Failed to clean up user data: $@");
        return 0;
    }
    return 1;
}

# Main hook handler
my $hook = shift @ARGV;
my $user = shift @ARGV;

unless ($hook && $user) {
    $logger->error("HostGuardian: Hook name and user are required");
    exit 1;
}

my %hook_handlers = (
    'pre_backup'     => sub { pause_scans($user) },
    'post_backup'    => sub { resume_scans($user) },
    'pre_restore'    => sub { stop_scans($user) },
    'post_restore'   => sub { enable_scheduled_tasks($user) },
    'pre_suspend'    => sub { stop_scans($user) && disable_scheduled_tasks($user) },
    'post_unsuspend' => sub { enable_scheduled_tasks($user) },
    'pre_terminate'  => sub { cleanup_user_data($user) }
);

if (exists $hook_handlers{$hook}) {
    exit($hook_handlers{$hook}->() ? 0 : 1);
} else {
    $logger->error("HostGuardian: Unknown hook: $hook");
    exit 1;
}

END {
    $dbh->disconnect if $dbh;
} 