package HostGuardian::Threat;

use strict;
use warnings;
use File::Copy;
use File::Path qw(make_path);
use Digest::SHA qw(sha256_hex);
use JSON::XS;
use MIME::Base64;

# Constructor
sub new {
    my ($class, %args) = @_;
    my $self = {
        id => $args{id},
        dbh => $args{dbh},
        quarantine_dir => '/usr/local/cpanel/base/hostguardian/quarantine',
        _data => undef,
    };
    bless $self, $class;
    
    $self->_load_threat_data();
    return $self;
}

# Load threat data from database
sub _load_threat_data {
    my $self = shift;
    
    my $sth = $self->{dbh}->prepare(
        "SELECT t.*, s.user_id 
         FROM hg_threats t 
         JOIN hg_scans s ON t.scan_id = s.id 
         WHERE t.id = ?"
    );
    $sth->execute($self->{id});
    $self->{_data} = $sth->fetchrow_hashref;
    
    die "Threat not found" unless $self->{_data};
}

# Handle threat actions
sub handle_action {
    my ($self, $action) = @_;
    
    if ($action eq 'quarantine') {
        return $self->_quarantine_file();
    }
    elsif ($action eq 'delete') {
        return $self->_delete_file();
    }
    elsif ($action eq 'whitelist') {
        return $self->_whitelist_file();
    }
    elsif ($action eq 'restore') {
        return $self->_restore_file();
    }
    else {
        return {
            success => 0,
            message => "Invalid action: $action"
        };
    }
}

# Quarantine infected file
sub _quarantine_file {
    my $self = shift;
    my $file_path = $self->{_data}->{file_path};
    
    return {success => 0, message => 'File not found'}
        unless -f $file_path;
    
    # Create quarantine directory if it doesn't exist
    my $quarantine_path = $self->_get_quarantine_path();
    make_path($quarantine_path);
    
    # Move file to quarantine
    my $quarantine_file = $quarantine_path . '/' . sha256_hex($file_path);
    if (move($file_path, $quarantine_file)) {
        # Update threat status
        my $sth = $self->{dbh}->prepare(
            "UPDATE hg_threats 
             SET status = 'quarantined',
                 quarantine_path = ?,
                 updated_at = NOW() 
             WHERE id = ?"
        );
        $sth->execute($quarantine_file, $self->{id});
        
        # Log action
        $self->_log_action('quarantine');
        
        return {
            success => 1,
            message => 'File quarantined successfully'
        };
    }
    
    return {
        success => 0,
        message => "Failed to quarantine file: $!"
    };
}

# Delete infected file
sub _delete_file {
    my $self = shift;
    my $file_path = $self->{_data}->{file_path};
    
    if (unlink($file_path)) {
        # Update threat status
        my $sth = $self->{dbh}->prepare(
            "UPDATE hg_threats 
             SET status = 'deleted',
                 updated_at = NOW() 
             WHERE id = ?"
        );
        $sth->execute($self->{id});
        
        # Log action
        $self->_log_action('delete');
        
        return {
            success => 1,
            message => 'File deleted successfully'
        };
    }
    
    return {
        success => 0,
        message => "Failed to delete file: $!"
    };
}

# Whitelist file
sub _whitelist_file {
    my $self = shift;
    my $file_path = $self->{_data}->{file_path};
    
    return {success => 0, message => 'File not found'}
        unless -f $file_path;
    
    # Calculate file hash
    open my $fh, '<', $file_path or return {
        success => 0,
        message => "Failed to open file: $!"
    };
    my $sha256 = Digest::SHA->new(256);
    $sha256->addfile($fh);
    my $hash = $sha256->hexdigest;
    close $fh;
    
    # Add to whitelist
    my $sth = $self->{dbh}->prepare(
        "INSERT INTO hg_whitelist 
         (file_hash, file_path, user_id, created_at) 
         VALUES (?, ?, ?, NOW())"
    );
    $sth->execute($hash, $file_path, $self->{_data}->{user_id});
    
    # Update threat status
    $sth = $self->{dbh}->prepare(
        "UPDATE hg_threats 
         SET status = 'whitelisted',
             updated_at = NOW() 
         WHERE id = ?"
    );
    $sth->execute($self->{id});
    
    # Log action
    $self->_log_action('whitelist');
    
    return {
        success => 1,
        message => 'File whitelisted successfully'
    };
}

# Restore quarantined file
sub _restore_file {
    my $self = shift;
    
    return {success => 0, message => 'File not quarantined'}
        unless $self->{_data}->{status} eq 'quarantined';
    
    my $quarantine_file = $self->{_data}->{quarantine_path};
    my $original_path = $self->{_data}->{file_path};
    
    if (move($quarantine_file, $original_path)) {
        # Update threat status
        my $sth = $self->{dbh}->prepare(
            "UPDATE hg_threats 
             SET status = 'restored',
                 quarantine_path = NULL,
                 updated_at = NOW() 
             WHERE id = ?"
        );
        $sth->execute($self->{id});
        
        # Log action
        $self->_log_action('restore');
        
        return {
            success => 1,
            message => 'File restored successfully'
        };
    }
    
    return {
        success => 0,
        message => "Failed to restore file: $!"
    };
}

# Get quarantine path for user
sub _get_quarantine_path {
    my $self = shift;
    return sprintf(
        "%s/%d/%s",
        $self->{quarantine_dir},
        $self->{_data}->{user_id},
        substr(sha256_hex($self->{_data}->{file_path}), 0, 2)
    );
}

# Log threat action
sub _log_action {
    my ($self, $action) = @_;
    
    my $sth = $self->{dbh}->prepare(
        "INSERT INTO hg_threat_log 
         (threat_id, action, user_id, created_at) 
         VALUES (?, ?, ?, NOW())"
    );
    $sth->execute(
        $self->{id},
        $action,
        $self->{_data}->{user_id}
    );
}

1; 