package HostGuardian::DB;

use strict;
use warnings;
use DBI;
use Cpanel::Config::LoadWwwAcct ();

my $DB_NAME = 'hostguardian';
my $DB_PREFIX = 'hg_';
my $_dbh;

# Get database connection
sub connect {
    return $_dbh if $_dbh && $_dbh->ping;
    
    my $conf = Cpanel::Config::LoadWwwAcct::loadwwwacct();
    die "Failed to load cPanel configuration" unless $conf;
    
    my $dsn = "DBI:mysql:database=$DB_NAME;host=localhost";
    $_dbh = DBI->connect($dsn, $conf->{'MYSQL_USERNAME'}, $conf->{'MYSQL_PASSWORD'}, {
        RaiseError => 1,
        AutoCommit => 1,
        mysql_enable_utf8 => 1,
    });
    
    return $_dbh;
}

# Close database connection
sub disconnect {
    if ($_dbh) {
        $_dbh->disconnect;
        undef $_dbh;
    }
}

# Begin transaction
sub begin_work {
    my $dbh = shift || connect();
    $dbh->begin_work;
}

# Commit transaction
sub commit {
    my $dbh = shift || connect();
    $dbh->commit;
}

# Rollback transaction
sub rollback {
    my $dbh = shift || connect();
    $dbh->rollback;
}

# Execute query with parameters
sub execute {
    my ($query, @params) = @_;
    my $dbh = connect();
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);
    return $sth;
}

# Get single row as hashref
sub get_row {
    my ($query, @params) = @_;
    my $sth = execute($query, @params);
    return $sth->fetchrow_hashref;
}

# Get multiple rows as array of hashrefs
sub get_rows {
    my ($query, @params) = @_;
    my $sth = execute($query, @params);
    my @rows;
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }
    return \@rows;
}

# Get single value
sub get_value {
    my ($query, @params) = @_;
    my $sth = execute($query, @params);
    my ($value) = $sth->fetchrow_array;
    return $value;
}

# Insert row and return last insert ID
sub insert {
    my ($table, $data) = @_;
    my $dbh = connect();
    
    my @columns = keys %$data;
    my $query = sprintf(
        "INSERT INTO %s%s (%s) VALUES (%s)",
        $DB_PREFIX,
        $table,
        join(',', @columns),
        join(',', map {'?'} @columns)
    );
    
    my $sth = $dbh->prepare($query);
    $sth->execute(map {$data->{$_}} @columns);
    
    return $dbh->last_insert_id(undef, undef, undef, undef);
}

# Update rows
sub update {
    my ($table, $data, $where, $where_params) = @_;
    my $dbh = connect();
    
    my @set_columns = keys %$data;
    my $query = sprintf(
        "UPDATE %s%s SET %s WHERE %s",
        $DB_PREFIX,
        $table,
        join(',', map {"$_=?"} @set_columns),
        $where
    );
    
    my $sth = $dbh->prepare($query);
    $sth->execute(
        (map {$data->{$_}} @set_columns),
        @$where_params
    );
    
    return $sth->rows;
}

# Delete rows
sub delete {
    my ($table, $where, $where_params) = @_;
    my $dbh = connect();
    
    my $query = sprintf(
        "DELETE FROM %s%s WHERE %s",
        $DB_PREFIX,
        $table,
        $where
    );
    
    my $sth = $dbh->prepare($query);
    $sth->execute(@$where_params);
    
    return $sth->rows;
}

# Check if table exists
sub table_exists {
    my $table = shift;
    my $dbh = connect();
    
    my $sth = $dbh->prepare("SHOW TABLES LIKE ?");
    $sth->execute($DB_PREFIX . $table);
    
    return $sth->rows > 0;
}

# Get table columns
sub get_columns {
    my $table = shift;
    my $dbh = connect();
    
    my $sth = $dbh->prepare("DESCRIBE " . $DB_PREFIX . $table);
    $sth->execute();
    
    my @columns;
    while (my $row = $sth->fetchrow_hashref) {
        push @columns, $row->{Field};
    }
    
    return \@columns;
}

# Handle cleanup on process exit
END {
    disconnect();
}

1; 