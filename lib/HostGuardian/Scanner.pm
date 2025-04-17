package HostGuardian::Scanner;

use strict;
use warnings;
use File::Find;
use Digest::SHA qw(sha256_hex);
use JSON::XS;
use DBI;
use Thread::Pool;
use Linux::Inotify2;
use MIME::Base64;
use LWP::UserAgent;

# Scanner instance attributes
sub new {
    my ($class, %args) = @_;
    my $self = {
        scan_id => $args{scan_id},
        user_id => $args{user_id},
        db_handle => $args{dbh},
        scan_type => $args{scan_type} || 'manual',
        max_threads => $args{max_threads} || 4,
        chunk_size => $args{chunk_size} || 1024,
        signatures => {},
        ml_model => undef,
        _stats => {
            total_files => 0,
            scanned_files => 0,
            infected_files => 0,
            start_time => time(),
        }
    };
    bless $self, $class;
    
    $self->_load_signatures();
    $self->_init_ml_model() if $args{enable_ml};
    return $self;
}

# Load virus signatures from database and files
sub _load_signatures {
    my $self = shift;
    my $sth = $self->{db_handle}->prepare(
        "SELECT signature_hash, threat_name, severity FROM hg_signatures WHERE active = 1"
    );
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        $self->{signatures}->{$row->{signature_hash}} = {
            name => $row->{threat_name},
            severity => $row->{severity}
        };
    }
}

# Initialize machine learning model
sub _init_ml_model {
    my $self = shift;
    # Load pre-trained model for ML-based detection
    eval {
        require AI::TensorFlow::Lite;
        $self->{ml_model} = AI::TensorFlow::Lite->new(
            model_path => '/usr/local/cpanel/base/hostguardian/models/threat_detection.tflite'
        );
    };
    warn "ML model initialization failed: $@" if $@;
}

# Main scanning function
sub scan_path {
    my ($self, $path) = @_;
    my $pool = Thread::Pool->new({
        min_workers => 1,
        max_workers => $self->{max_threads},
        on_error => sub { warn "Thread error: @_" }
    });

    my @files;
    find(sub {
        return if -d $_;
        push @files, $File::Find::name;
        if (@files >= $self->{chunk_size}) {
            $pool->job(sub { $self->_scan_files(@files) });
            @files = ();
        }
    }, $path);

    # Scan remaining files
    $pool->job(sub { $self->_scan_files(@files) }) if @files;
    $pool->shutdown();
}

# Scan individual files
sub _scan_files {
    my ($self, @files) = @_;
    foreach my $file (@files) {
        $self->_scan_file($file);
    }
}

# Scan a single file
sub _scan_file {
    my ($self, $file) = @_;
    return unless -f $file && -r $file;

    $self->{_stats}->{total_files}++;
    
    # Get file metadata
    my $size = -s $file;
    my $mime = $self->_get_mime_type($file);
    
    # Skip if file is too large or binary
    return if $size > 50_000_000; # 50MB limit
    
    # Calculate file hash
    open my $fh, '<', $file or return;
    my $sha256 = Digest::SHA->new(256);
    $sha256->addfile($fh);
    my $hash = $sha256->hexdigest;
    close $fh;
    
    # Check against known signatures
    if (exists $self->{signatures}->{$hash}) {
        $self->_report_threat($file, {
            type => 'signature_match',
            name => $self->{signatures}->{$hash}->{name},
            severity => $self->{signatures}->{$hash}->{severity}
        });
        return;
    }
    
    # Perform heuristic analysis
    if ($self->_heuristic_check($file)) {
        $self->_report_threat($file, {
            type => 'heuristic',
            name => 'Suspicious_Behavior',
            severity => 'medium'
        });
        return;
    }
    
    # ML-based analysis if available
    if ($self->{ml_model} && $self->_ml_check($file)) {
        $self->_report_threat($file, {
            type => 'ml_detection',
            name => 'ML_Suspicious',
            severity => 'medium'
        });
        return;
    }
    
    $self->{_stats}->{scanned_files}++;
}

# Report detected threat
sub _report_threat {
    my ($self, $file, $threat_info) = @_;
    
    $self->{_stats}->{infected_files}++;
    
    my $sth = $self->{db_handle}->prepare(q{
        INSERT INTO hg_threats 
        (scan_id, file_path, threat_type, threat_name, severity, status)
        VALUES (?, ?, ?, ?, ?, 'detected')
    });
    
    $sth->execute(
        $self->{scan_id},
        $file,
        $threat_info->{type},
        $threat_info->{name},
        $threat_info->{severity}
    );
}

# Heuristic analysis
sub _heuristic_check {
    my ($self, $file) = @_;
    open my $fh, '<', $file or return 0;
    my $content;
    read($fh, $content, 1024); # Read first 1KB
    close $fh;
    
    # Check for common malware patterns
    return 1 if $content =~ /eval\(\$_POST/;
    return 1 if $content =~ /base64_decode\(\$_/;
    return 1 if $content =~ /system\(\$_/;
    return 1 if $content =~ /eval\(base64_decode/;
    
    return 0;
}

# ML-based analysis
sub _ml_check {
    my ($self, $file) = @_;
    return 0 unless $self->{ml_model};
    
    # Extract features and run through ML model
    my $features = $self->_extract_ml_features($file);
    my $prediction = $self->{ml_model}->predict($features);
    
    return $prediction->{malware_probability} > 0.8;
}

# Get file MIME type
sub _get_mime_type {
    my ($self, $file) = @_;
    my $mime = `file -b --mime-type "$file"`;
    chomp $mime;
    return $mime;
}

# Get current scan statistics
sub get_stats {
    my $self = shift;
    return {
        %{$self->{_stats}},
        elapsed_time => time() - $self->{_stats}->{start_time}
    };
}

1; 