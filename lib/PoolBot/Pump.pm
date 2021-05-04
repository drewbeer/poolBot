package PoolBot::Pump;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(pumpInfo pumpRun pumpStop);

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use FindBin qw($Bin);
use JSON;
use PoolBot::Common;

sub pumpInfo {
  my $pumpNumber = shift;

  my $log = get_logger("PoolBot::Pump");
  my $pumpCfg = getConfig('pump');

  unless ($pumpNumber) {
    $pumpNumber = 1;
  }

  $log->debug("fetching pump info for $pumpNumber");
  my $pumpJson = getURL("$pumpCfg->{'url'}/pump");

  my $pumpStatus = ();
  if ($pumpJson) {
    my $pumpData = decode_json $pumpJson;
    $pumpStatus = $pumpData->{'pump'}{$pumpNumber};
  }

  # if its not set, set it
  unless ($pumpStatus->{'currentrunning'}->{'mode'} || $pumpJson) {
      $pumpStatus->{'currentrunning'}->{'mode'} = 'unreachable';
      $pumpStatus->{'currentrunning'}->{'value'} = 0;
      $pumpStatus->{'currentrunning'}->{'remainingduration'} = 0;
      $log->error("failed to connect to the pump");
  }

  return $pumpStatus;
}

sub pumpRun {
  my $pump = shift;
  my $program = shift;
  my $duration = shift;

  my $log = get_logger("PoolBot::Pump");
  my $pumpCfg = getConfig('pump');

  $log->debug("running pump $pump with program $program for $duration minutes");
  my $url = "$pumpCfg->{'url'}/pumpCommand/run/pump/$pump/program/$program/duration/$duration";
  my $pumpJson = getURL($url);
  my $pumpData = decode_json $pumpJson;

  return $pumpData;
}

sub pumpStop {
  my $pump = shift;

  my $log = get_logger("PoolBot::Pump");
  my $pumpCfg = getConfig('pump');

  $log->debug("stopping pump $pump");
  my $url = "$pumpCfg->{'url'}/pumpCommand/off/pump/$pump";
  my $pumpJson = getURL($url);
  my $pumpData = decode_json $pumpJson;

  return $pumpData;
}
