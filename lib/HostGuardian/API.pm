package HostGuardian::API;

use strict;
use warnings;
use JSON::XS;
use LWP::UserAgent;
use HTTP::Request;
use MIME::Base64;
use Digest::SHA qw(hmac_sha256_hex);

# Constructor
sub new {
    my ($class, %args) = @_;
    
    die "API key is required" unless $args{api_key};
    die "Endpoint URL is required" unless $args{endpoint};
    
    my $self = {
        api_key => $args{api_key},
        endpoint => $args{endpoint},
        timeout => $args{timeout} || 30,
        ua => LWP::UserAgent->new(
            timeout => $args{timeout} || 30,
            ssl_opts => { verify_hostname => 1 }
        ),
    };
    
    bless $self, $class;
    return $self;
}

# Make API request
sub _request {
    my ($self, $method, $path, $data) = @_;
    
    my $url = $self->{endpoint} . $path;
    my $timestamp = time();
    my $nonce = _generate_nonce();
    
    # Prepare request
    my $request = HTTP::Request->new($method => $url);
    $request->header('Content-Type' => 'application/json');
    $request->header('X-API-Key' => $self->{api_key});
    $request->header('X-Timestamp' => $timestamp);
    $request->header('X-Nonce' => $nonce);
    
    # Add request body if data is provided
    if ($data) {
        my $json = encode_json($data);
        $request->content($json);
        
        # Calculate signature
        my $signature = $self->_calculate_signature(
            $method,
            $path,
            $timestamp,
            $nonce,
            $json
        );
        $request->header('X-Signature' => $signature);
    }
    
    # Send request
    my $response = $self->{ua}->request($request);
    
    # Handle response
    if ($response->is_success) {
        my $content = $response->decoded_content;
        return decode_json($content);
    }
    else {
        die sprintf(
            "API request failed: %s - %s",
            $response->code,
            $response->message
        );
    }
}

# Calculate request signature
sub _calculate_signature {
    my ($self, $method, $path, $timestamp, $nonce, $body) = @_;
    
    my $string_to_sign = join("\n",
        $method,
        $path,
        $timestamp,
        $nonce,
        $body || ''
    );
    
    return hmac_sha256_hex($string_to_sign, $self->{api_key});
}

# Generate random nonce
sub _generate_nonce {
    my @chars = ('a'..'z', 'A'..'Z', '0'..'9');
    my $nonce = '';
    $nonce .= $chars[rand @chars] for 1..16;
    return $nonce;
}

# Start a new scan
sub start_scan {
    my ($self, %args) = @_;
    
    die "Path is required" unless $args{path};
    
    return $self->_request('POST', '/v1/scans', {
        path => $args{path},
        type => $args{type} || 'full',
        options => $args{options} || {}
    });
}

# Get scan status
sub get_scan_status {
    my ($self, $scan_id) = @_;
    
    die "Scan ID is required" unless $scan_id;
    
    return $self->_request('GET', "/v1/scans/$scan_id");
}

# Get scan results
sub get_scan_results {
    my ($self, $scan_id) = @_;
    
    die "Scan ID is required" unless $scan_id;
    
    return $self->_request('GET', "/v1/scans/$scan_id/results");
}

# Manage threat
sub manage_threat {
    my ($self, %args) = @_;
    
    die "Threat ID is required" unless $args{threat_id};
    die "Action is required" unless $args{action};
    
    return $self->_request('POST', "/v1/threats/$args{threat_id}/actions", {
        action => $args{action},
        options => $args{options} || {}
    });
}

# Get threat details
sub get_threat {
    my ($self, $threat_id) = @_;
    
    die "Threat ID is required" unless $threat_id;
    
    return $self->_request('GET', "/v1/threats/$threat_id");
}

# Get system statistics
sub get_statistics {
    my ($self, %args) = @_;
    
    my $path = '/v1/statistics';
    $path .= "?period=$args{period}" if $args{period};
    
    return $self->_request('GET', $path);
}

# Get quarantined files
sub get_quarantine {
    my ($self, %args) = @_;
    
    my $path = '/v1/quarantine';
    $path .= "?page=$args{page}" if $args{page};
    $path .= "&per_page=$args{per_page}" if $args{per_page};
    
    return $self->_request('GET', $path);
}

# Update settings
sub update_settings {
    my ($self, %settings) = @_;
    
    return $self->_request('PUT', '/v1/settings', \%settings);
}

# Get current settings
sub get_settings {
    my $self = shift;
    
    return $self->_request('GET', '/v1/settings');
}

# Get server status
sub get_server_status {
    my $self = shift;
    
    return $self->_request('GET', '/v1/status');
}

# Get update status
sub get_update_status {
    my $self = shift;
    
    return $self->_request('GET', '/v1/updates/status');
}

# Check for updates
sub check_updates {
    my $self = shift;
    
    return $self->_request('POST', '/v1/updates/check');
}

# Install updates
sub install_updates {
    my $self = shift;
    
    return $self->_request('POST', '/v1/updates/install');
}

1; 