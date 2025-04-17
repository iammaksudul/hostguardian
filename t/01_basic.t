#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use DBI;
use Config::Simple;

# Test configuration loading
my $config_file = '/usr/local/cpanel/base/hostguardian/config.ini';
ok(-f $config_file, 'Configuration file exists');

my $cfg = Config::Simple->new($config_file);
ok($cfg, 'Can parse configuration file');

# Test database connection
my $dbh = DBI->connect(
    "DBI:mysql:database=" . $cfg->param('database.name') . 
    ";host=" . $cfg->param('database.host'),
    $cfg->param('database.user'),
    $cfg->param('database.pass'),
    { RaiseError => 1, PrintError => 0 }
);
ok($dbh, 'Can connect to database');

# Test required directories
my @required_dirs = (
    '/usr/local/cpanel/base/hostguardian',
    '/usr/local/cpanel/base/hostguardian/quarantine',
    '/var/log/hostguardian'
);

for my $dir (@required_dirs) {
    ok(-d $dir, "Directory $dir exists");
    ok(-w $dir, "Directory $dir is writable");
}

# Test required files
my @required_files = (
    '/usr/local/cpanel/Cpanel/HostGuardian/Hooks.pm',
    '/usr/local/cpanel/whm/docroot/cgi/hostguardian.cgi',
    '/usr/local/cpanel/base/frontend/paper_lantern/hostguardian/hostguardian.cgi'
);

for my $file (@required_files) {
    ok(-f $file, "File $file exists");
    ok(-x $file, "File $file is executable") if $file =~ /\.cgi$/;
}

# Test database tables
my @required_tables = qw(scans threats quarantine scheduled_tasks statistics);
for my $table (@required_tables) {
    my $sth = $dbh->prepare("SHOW TABLES LIKE ?");
    $sth->execute($table);
    ok($sth->rows, "Table $table exists");
}

# Clean up
$dbh->disconnect if $dbh;

done_testing(); 