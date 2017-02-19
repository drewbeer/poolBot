#!/usr/bin/perl
package PoolPi::WebServer;
use strict;
use warnings;
use HTTP::Server::Simple::CGI;
use base qw(HTTP::Server::Simple::CGI);


my %dispatch = (
   '/ping' => \&resp_pong,
   # ...
);


# get the thread id

# check to see if we should run any commands

# wait

# die if needed


## Functions

### Basics
sub stop {
  my $pid = shift;
  kill 1, $pid;
}

sub start {
  my $pid = PoolPI::WebServer->new(8080)->background();
  return $pid;
}


# requests
sub handle_request {
  my $self = shift;
  my $cgi  = shift;

  my $path = $cgi->path_info();
  my $handler = $dispatch{$path};

  if (ref($handler) eq "CODE") {
   print "HTTP/1.0 200 OK\r\n";
   $handler->($cgi);

  } else {
   print "HTTP/1.0 404 Not found\r\n";
   print $cgi->header,
     $cgi->start_html('Not found'),
     $cgi->h1('Not found'),
     $cgi->end_html;
  }
}

sub resp_pong {
  return "pong";
}
