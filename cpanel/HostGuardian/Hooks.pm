package Cpanel::HostGuardian::Hooks;

use strict;
use warnings;
use Config::Simple;
use DBI;
use Time::Piece;
use Cpanel::Logger ();

our $VERSION = '1.0.0';

# Initialize logger
my $logger = Cpanel::Logger->init();

# Configuration
my $CONFIG_FILE = '/usr/local/cpanel/base/hostguardian/config.ini';
my $config = Config::Simple->new($CONFIG_FILE);

# Database connection with retry
sub _get_dbh {
    my $max_retries = 3;
    my $retry_delay = 2;
    my $attempt = 0;
    
    while ($attempt < $max_retries) {
        eval {
            return DBI->connect(
                "DBI:mysql:database=" . $config->param('database.name') . 
                ";host=" . $config->param('database.host'),
                $config->param('database.user'),
                $config->param('database.pass'),
                { 
                    RaiseError => 1,
                    PrintError => 0,
                    mysql_enable_utf8mb4 => 1,
                    mysql_auto_reconnect => 1
                }
            );
        };
        if ($@) {
            $logger->warn("Database connection attempt $attempt failed: $@");
            $attempt++;
            sleep $retry_delay if $attempt < $max_retries;
        } else {
            return $dbh;
        }
    }
    die "Failed to connect to database after $max_retries attempts";
}

# Hook: Pre-backup
sub pre_backup {
    my ($context) = @_;
    my $username = $context->{user};
    
    eval {
        my $dbh = _get_dbh();
        $logger->info("Running pre-backup hook for user: $username");
        
        # Begin transaction
        $dbh->begin_work;
        
        # Pause any active scans
        $dbh->do(
            "UPDATE scans SET status = 'paused', updated_at = NOW() WHERE username = ? AND status = 'running'",
            undef,
            $username
        );
        
        # Log statistics
        $dbh->do(
            "INSERT INTO statistics (username, date, action, details) VALUES (?, CURDATE(), 'backup_start', 'Paused active scans')",
            undef,
            $username
        );
        
        $dbh->commit;
        $dbh->disconnect;
    };
    if ($@) {
        my $error = $@;
        eval { $dbh->rollback if $dbh; };
        $logger->error("Error in pre_backup hook: $error");
        return 0;
    }
    return 1;
}

# Hook: Post-backup
sub post_backup {
    my ($context) = @_;
    my $username = $context->{user};
    
    eval {
        my $dbh = _get_dbh();
        $logger->info("Running post-backup hook for user: $username");
        
        $dbh->begin_work;
        
        # Resume paused scans
        $dbh->do(
            "UPDATE scans SET status = 'running', updated_at = NOW() WHERE username = ? AND status = 'paused'",
            undef,
            $username
        );
        
        # Log completion
        $dbh->do(
            "INSERT INTO statistics (username, date, action, details) VALUES (?, CURDATE(), 'backup_complete', 'Resumed paused scans')",
            undef,
            $username
        );
        
        $dbh->commit;
        $dbh->disconnect;
    };
    if ($@) {
        my $error = $@;
        eval { $dbh->rollback if $dbh; };
        $logger->error("Error in post_backup hook: $error");
        return 0;
    }
    return 1;
}

# Hook: Pre-restore
sub pre_restore {
    my ($context) = @_;
    my $username = $context->{user};
    
    eval {
        my $dbh = _get_dbh();
        $logger->info("Running pre-restore hook for user: $username");
        
        $dbh->begin_work;
        
        # Stop all active scans
        $dbh->do(
            "UPDATE scans SET status = 'stopped', updated_at = NOW() WHERE username = ? AND status IN ('running', 'paused')",
            undef,
            $username
        );
        
        # Log action
        $dbh->do(
            "INSERT INTO statistics (username, date, action, details) VALUES (?, CURDATE(), 'restore_start', 'Stopped all scans')",
            undef,
            $username
        );
        
        $dbh->commit;
        $dbh->disconnect;
    };
    if ($@) {
        my $error = $@;
        eval { $dbh->rollback if $dbh; };
        $logger->error("Error in pre_restore hook: $error");
        return 0;
    }
    return 1;
}

# Hook: Post-restore
sub post_restore {
    my ($context) = @_;
    my $username = $context->{user};
    
    eval {
        my $dbh = _get_dbh();
        $logger->info("Running post-restore hook for user: $username");
        
        $dbh->begin_work;
        
        # Start a new security scan
        $dbh->do(
            "INSERT INTO scans (username, type, status, created_at, updated_at) VALUES (?, 'quick', 'queued', NOW(), NOW())",
            undef,
            $username
        );
        
        # Log action
        $dbh->do(
            "INSERT INTO statistics (username, date, action, details) VALUES (?, CURDATE(), 'restore_complete', 'Queued security scan')",
            undef,
            $username
        );
        
        $dbh->commit;
        $dbh->disconnect;
    };
    if ($@) {
        my $error = $@;
        eval { $dbh->rollback if $dbh; };
        $logger->error("Error in post_restore hook: $error");
        return 0;
    }
    return 1;
}

# Hook: Pre-suspend
sub pre_suspend {
    my ($context) = @_;
    my $username = $context->{user};
    
    eval {
        my $dbh = _get_dbh();
        # Stop all scans and scheduled tasks
        $dbh->do(
            "UPDATE scans SET status = 'stopped', updated_at = NOW() WHERE username = ? AND status IN ('running', 'paused', 'queued')",
            undef,
            $username
        );
        $dbh->do(
            "UPDATE scheduled_tasks SET status = 'disabled', updated_at = NOW() WHERE username = ? AND status = 'enabled'",
            undef,
            $username
        );
        $dbh->disconnect;
    };
    if ($@) {
        warn "Error in pre_suspend hook: $@";
        return 0;
    }
    return 1;
}

# Hook: Post-unsuspend
sub post_unsuspend {
    my ($context) = @_;
    my $username = $context->{user};
    
    eval {
        my $dbh = _get_dbh();
        # Re-enable scheduled tasks and start a security scan
        $dbh->do(
            "UPDATE scheduled_tasks SET status = 'enabled', updated_at = NOW() WHERE username = ? AND status = 'disabled'",
            undef,
            $username
        );
        $dbh->do(
            "INSERT INTO scans (username, type, status, created_at, updated_at) VALUES (?, 'quick', 'queued', NOW(), NOW())",
            undef,
            $username
        );
        $dbh->disconnect;
    };
    if ($@) {
        warn "Error in post_unsuspend hook: $@";
        return 0;
    }
    return 1;
}

# Hook: Pre-terminate
sub pre_terminate {
    my ($context) = @_;
    my $username = $context->{user};
    
    eval {
        my $dbh = _get_dbh();
        # Clean up all user data
        $dbh->do("DELETE FROM scans WHERE username = ?", undef, $username);
        $dbh->do("DELETE FROM threats WHERE username = ?", undef, $username);
        $dbh->do("DELETE FROM scheduled_tasks WHERE username = ?", undef, $username);
        $dbh->do("DELETE FROM quarantine WHERE username = ?", undef, $username);
        
        # Clean up quarantined files
        my $quarantine_dir = "$config->{quarantine}->{path}/$username";
        if (-d $quarantine_dir) {
            system("rm", "-rf", $quarantine_dir);
        }
        
        $dbh->disconnect;
    };
    if ($@) {
        warn "Error in pre_terminate hook: $@";
        return 0;
    }
    return 1;
}

# Hook registration info
sub describe {
    return [
        {
            category => "Cpanel",
            event => "BACKUP",
            stage => "pre",
            hook => "Cpanel::HostGuardian::Hooks::pre_backup",
            exectype => "module",
            weight => 0,
            description => "Pauses active virus scans before backup"
        },
        {
            category => "Cpanel",
            event => "BACKUP",
            stage => "post",
            hook => "Cpanel::HostGuardian::Hooks::post_backup",
            exectype => "module",
            weight => 0,
            description => "Resumes paused virus scans after backup"
        },
        {
            category => "Cpanel",
            event => "RESTORE",
            stage => "pre",
            hook => "Cpanel::HostGuardian::Hooks::pre_restore",
            exectype => "module",
            weight => 0,
            description => "Stops active virus scans before restore"
        },
        {
            category => "Cpanel",
            event => "RESTORE",
            stage => "post",
            hook => "Cpanel::HostGuardian::Hooks::post_restore",
            exectype => "module",
            weight => 0,
            description => "Initiates security scan after restore"
        }
    ];
}

1; 