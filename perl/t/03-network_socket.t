#!/usr/bin/env perl

use strict;
use warnings;

use Check::Fork qw(check_fork);
use Check::Socket qw(check_socket);
use FCGI;
use FCGI::Client;
use IO::Socket::IP;
use Test::More 'tests' => 4;

check_fork() || plan skip_all => $Check::Fork::ERROR_MESSAGE;
check_socket() || plan skip_all => $Check::Socket::ERROR_MESSAGE;

my $port = 8888;

# Client
if (my $pid = fork()) {
    my $right_ret = <<'END';
Content-Type: text/plain

END

    my ($stdout, $stderr) = client_request($port);
    is($stdout, $right_ret."0\n", 'Test first round on stdout.');
    is($stderr, undef, 'Test first round on stderr.');

    ($stdout, $stderr) = client_request($port);
    is($stdout, $right_ret."1\n", 'Test second round on stdout.');
    is($stderr, undef, 'Test second round on stderr.');

# Server
} elsif (defined $pid) {
    my $fcgi_socket = FCGI::OpenSocket(':'.$port, 5);
    my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV, $fcgi_socket);

    # Only two cycles.
    my $count = 0;
    while ($count < 2 && $request->Accept() >= 0) {
        print "Content-Type: text/plain\n\n";
        print $count++."\n";
    }
    exit;

} else {
    die $!;
}

sub client_request {
    my $port = shift;

    my $sock = IO::Socket::IP->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
    ) or die $!;

    my $client = FCGI::Client::Connection->new(sock => $sock);
    my ($stdout, $stderr) = $client->request({
        REQUEST_METHOD => 'GET',
    }, '');

    return ($stdout, $stderr);
}
