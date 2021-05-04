#!/usr/bin/env perl
# free as in beer
# developed by drew.beer
# if your pump explodes, its probably because
# you didn't drink enough beer.

use strict;
use warnings;
use Fcntl qw(:flock);
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Coro;
use Log::Log4perl;

use PoolBot::Common;
use PoolBot::HTTPD;
use PoolBot::System;
use PoolBot::Scheduler;
use PoolBot::MatterMost;

# termination flags.
my $term = 0;
$SIG{INT}  = \&signal_handler;
$SIG{TERM} = \&signal_handler;

# check for lock
my $lockFile = "$Bin/../tmp/poolBot.lock";
open(my $fhpid, '>', $lockFile) or die "error: open $lockFile: $!";
flock($fhpid, LOCK_EX|LOCK_NB) or die "already running";

# log file setup
Log::Log4perl->init("$Bin/../etc/log.conf");
my $log = Log::Log4perl->get_logger("poolBot");

$log->info("starting poolBot");
notifyMatter("starting poolBot");

# initialize startup
initSystem();

# # start httpd
$log->info("starting web");
async {
  return if $term;
  startHTTPd();
};

# start the scheduler
$log->info("starting scheduler");
async {
  return if $term;
  startScheduler();
};

# lets be idle!
while () {
  use Coro::AnyEvent;
  Coro::AnyEvent::sleep 10;
  $log->debug("ping");
  if ($term) {
   $log->info("system terminating");
   exit;
  }

  # check the health, and send the stats
  heartbeat();
}

sub signal_handler {
    $log->info('caught shutdown, please wait');
    systemShutdown();
    $term = 1;
}

1;
