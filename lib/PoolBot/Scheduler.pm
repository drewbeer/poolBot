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
use PoolBot::MatterMost;

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
      my @taskDetails = split(/\,/, $schedule->{$task});
      $log->info("adding $task at $taskDetails[0]");
      notifyMatter("adding $task at $taskDetails[0]");

      # add the cron entry
      $cron->debug(1)->add(
          $taskDetails[0], name   => $task, single => 1, \&schedRun,
      );
      $cronCount++;
    }
  } else {
    my @taskDetails = split(/\,/, $schedule->{$schedule->{'tasks'}});
    $log->info("adding $schedule->{'tasks'} at $taskDetails[0] hour");
    notifyMatter("adding $schedule->{'tasks'} at $taskDetails[0] hour");

    # add the cron entry
    $cron->debug(1)->add(
        $taskDetails[0], name   => $schedule->{'tasks'}, single => 1,
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
    my ($time, $mode) = split(/\,/, $schedule->{$jobName});
    servicePumpController($mode);
  } else {
    my ($time, $modeName) = split(/\,/, $schedule->{$jobName});
    modeRun($modeName);
  }

  $cv->end
}
