package PoolBot::Scheduler;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(startScheduler schedTest);

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Log::Log4perl qw(get_logger);
use AnyEvent::DateTime::Cron;
use PoolBot::Common;
use PoolBot::System;

# we should load the cron and
sub startScheduler {

  my $log = get_logger("PoolBot::Scheduler");
  my $schedule = getConfig('schedule');
  my $cron = AnyEvent::DateTime::Cron->new();

  $log->info("loading schedules");
  my $cronCount = 0;

  # if there are multiple tasks
  if(ref($schedule->{'tasks'}) eq 'ARRAY') {
    foreach my $task (@{$schedule->{'tasks'}}) {
      my ($time, $program, $duration, $relay) = split(/\|/, $schedule->{$task});
      $log->info("adding $task at $time");

      # add the cron entry
      $cron->debug(1)->add(
          $time, name   => $task, single => 1, \&schedRun,
      );
      $cronCount++;
    }
  } else {
    my ($time, $program, $duration, $relay) = split(/\|/, $schedule->{$schedule->{'tasks'}});
    $log->info("adding $schedule->{'tasks'} at $time hour");

    # add the cron entry
    $cron->debug(1)->add(
        $time, name   => $schedule->{'tasks'}, single => 1,
        \&schedRun,
    );
    $cronCount++;
  }

  $log->info("cron started with $cronCount tasks");
  my $cv = $cron->start;
  $cv->recv;

}

sub schedRun {
  my $cv = shift;
  my $job = shift;

  my $log = get_logger("PoolBot::Scheduler::schedRun");

  my $jobName = $job->{'name'};
  $log->info("schedule triggered for $jobName");

  $cv->begin;
  my $schedule = getConfig('schedule');

  # pool maint schedule
  if ($jobName =~ /^pumpService/) {
    my ($time, $mode) = split(/\|/, $schedule->{$jobName});
    servicePumpController($mode);
  } else {
    my ($time, $program, $duration, $relay) = split(/\|/, $schedule->{$jobName});
    runPool($program, $duration, $relay);
  }

  $cv->end
}
