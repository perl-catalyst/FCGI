#!/usr/bin/env perl

use strict;
use warnings;

use Config;
use FCGI;
use FCGI::Client;
use File::Temp qw(tempfile);
use IO::Socket;
use Test::More 'tests' => 4;

BEGIN {
	my $reason;
	my $can_fork = $Config{d_fork}
		|| (
			($^O eq 'MSWin32' || $^O eq 'NetWare')
			and $Config{useithreads}
			and $Config{ccflags} =~ /-DPERL_IMPLICIT_SYS/
		);
	if ($ENV{PERL_CORE} and $Config{'extensions'} !~ /\bSocket\b/) {
		$reason = 'Socket extension unavailable';
	} elsif ($ENV{PERL_CORE} and $Config{'extensions'} !~ /\bIO\b/) {
		$reason = 'IO extension unavailable';
	} elsif ($^O eq 'os2') {
		eval { IO::Socket::pack_sockaddr_un('/foo/bar') || 1 };
		if ($@ !~ /not implemented/) {
			$reason = 'compiled without TCP/IP stack v4';
		}
	} elsif ($^O =~ m/^(?:qnx|nto|vos)$/ ) {
		$reason = "UNIX domain sockets not implemented on $^O";
	} elsif (! $can_fork) {
		$reason = 'no fork';
	} elsif ($^O eq 'MSWin32') {
		if ($ENV{CONTINUOUS_INTEGRATION}) {
			# https://github.com/Perl/perl5/issues/17429
			$reason = 'Skipping on Windows CI';
		} else {
			# https://github.com/Perl/perl5/issues/17575
			if (! eval { socket(my $sock, PF_UNIX, SOCK_STREAM, 0) }) {
				$reason = "AF_UNIX unavailable or disabled on this platform"
			}
		}
	}

	if ($reason) {
		print "1..0 # Skip: $reason\n";
		exit 0;
	}
}

my (undef, $unix_socket_file) = tempfile();
my $fcgi_socket = FCGI::OpenSocket($unix_socket_file, 5);

# Client
if (my $pid = fork()) {
	my $right_ret = <<'END';
Content-Type: text/plain

END

	my ($stdout, $stderr) = client_request($unix_socket_file);
	is($stdout, $right_ret."0\n", 'Test first round on stdout.');
	is($stderr, undef, 'Test first round on stderr.');

	($stdout, $stderr) = client_request($unix_socket_file);
	is($stdout, $right_ret."1\n", 'Test second round on stdout.');
	is($stderr, undef, 'Test second round on stderr.');

# Server
} elsif (defined $pid) {
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

# Cleanup.
FCGI::CloseSocket($fcgi_socket);
unlink $unix_socket_file;

sub client_request {
	my $unix_socket_file = shift;

	my $sock = IO::Socket::UNIX->new(
		Peer => $unix_socket_file,
	) or die $!;
	my $client = FCGI::Client::Connection->new(sock => $sock);
	my ($stdout, $stderr) = $client->request({
		REQUEST_METHOD => 'GET',
	}, '');

	return ($stdout, $stderr);
}
