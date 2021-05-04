package PoolBot::System;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(heartbeat initSystem getSystemInfo systemShutdown runPool stopPool servicePumpController);

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use FindBin qw($Bin);
use PoolBot::Common;
use PoolBot::MatterMost;
use PoolBot::Pump;
use PoolBot::Relays;
use PoolBot::InfluxDB;

sub runPool {
  my $program = shift;
  my $duration = shift;
  my $relay = shift;

  my $log = get_logger("PoolBot::System");
  my $pump = 1;

  my $message = "pool starting, setting pump $pump to program $program, for $duration";
  $log->info($message);
  notifyMatter($message);
  pumpRun($pump, $program, $duration);

  if ($relay) {
    $log->debug("starting relay $relay");
    relaySet($relay, 1);
  }

  return $message;
}

sub stopPool {
  my $relay = shift;

  my $log = get_logger("PoolBot::System");
  my $pump = 1;

  my $message = "stopping pool";
  $log->info($message);
  notifyMatter($message);
  pumpStop($pump);

  if ($relay) {
    $log->debug("starting relay $relay");
    relaySet($relay, 0);
  }
  return $message;
}


sub getSystemInfo {
  my $log = get_logger("PoolBot::System");
  my $sysInfo = ();
  $sysInfo->{'pump'} = pumpInfo();
  $sysInfo->{'relays'} = showRelays();
  $sysInfo->{'chassis'} = chassisEnv();
  $log->debug('finished getting systemInfo');
  return $sysInfo;
}

sub initSystem {
  my $log = get_logger("PoolBot::System");
  $log->debug("initializing system");
  initRelays();
}

sub heartbeat {
  my $log = get_logger("PoolBot::System");

  $log->debug('checking system health');
  my $status = getSystemInfo();
  my $pumpStatus = $status->{'pump'};
  my $relayStatus = $status->{'relays'};

  # check if the pump is off, and if we should be turning off relays
  if (($pumpStatus->{'currentrunning'}->{'mode'} eq 'off') || ($pumpStatus->{'currentrunning'}->{'mode'} eq 'unreachable')) {
    # status log
    $log->info("Pump is $pumpStatus->{'currentrunning'}->{'mode'}");

    ## do the health check
    # turn off salt if its on
    if ($relayStatus->{'salt'}) {
      $log->warn('pump may be off, turning off salt');
      notifyMatter("pump is $pumpStatus->{'currentrunning'}->{'mode'}, shutting down chlorine generator");
      relaySet('salt', 0);
    }

    # turn off heater if its on
    if ($relayStatus->{'heater'}) {
      $log->warn('monFork: pump may be off, turning off heater');
      relaySet('heater', 0);
    }

  } else {
    # pump is running
    $log->info("Pump is running $pumpStatus->{'currentrunning'}->{'mode'} at $pumpStatus->{'rpm'} using $pumpStatus->{'watts'} watts, with $pumpStatus->{'currentrunning'}->{'remainingduration'} minutes remaining");
  }

  # send the stats
  doStats($status);

}

sub doStats {
  my $data = shift;
  my $log = get_logger("PoolBot::System");

  # first process pump data
  if ($data->{'pump'}) {
    my $tags = { location=>'pool', pump=>1};
    my $pStats = ();
    foreach my $field (keys %{$data->{'pump'}}) {

      # handle the current running stuff
      if ($field eq 'currentrunning') {
        my $runStats = $data->{'pump'}->{'currentrunning'};
        $pStats->{'status'} = $runStats->{'mode'};
        $pStats->{'program'} = $runStats->{'value'};
        $pStats->{'progDuration'} = int2float($runStats->{'remainingduration'});
        next;
      }

      if ($field eq 'externalProgram') {
        next;
      }

      # fix duration
      if ($field eq 'duration') {
        $data->{'pump'}->{'duration'} = int2float($data->{'pump'}->{'duration'});
      }

      # fix power
      if ($field eq 'power') {
        $data->{'pump'}->{'power'} = int2float($data->{'pump'}->{'power'});
      }

      $pStats->{$field} = $data->{'pump'}->{$field};
    }
    writeInflux('pool_pump',$pStats, $tags);
  }


  # do relays
  if ($data->{'relays'}) {
    foreach my $relay (keys %{$data->{'relays'}}) {
      my $relayStatus = ();
      my $tags = { location=>'pool', relay => $relay };
      $relayStatus->{'status'} = $data->{'relays'}->{$relay};
      writeInflux('pool_relays',$relayStatus, $tags);
    }

  }

  if ($data->{'chassis'}) {
    my $tags = { location=>'pool'};
    writeInflux('pool_chassis',$data->{'chassis'}, $tags);
  }

}

sub chassisEnv {
  my $chassis = ();
  my $log = get_logger("PoolBot::System");
  my $sysConfig = getConfig('system');

  $log->debug("getting chassis ENV");
  # temperature and humidity
  my $output = `$Bin/$sysConfig->{'envCMD'}`;
  chomp $output;
  if ($output =~ /^\d+/) {
    ($chassis->{'temp'},$chassis->{'humidity'}) = split(/,/,$output);
    $log->debug("got $chassis->{'temp'} and $chassis->{'humidity'}");
  } else {
    $chassis->{'temp'} = 0;
    $chassis->{'humidity'} = 0;
  }

  return $chassis;
}

sub systemShutdown {
  my $log = get_logger("PoolBot::System");
  $log->info("system is shutting down");

  # shutdown all the relays
  relayShutdown();
}

sub servicePumpController {
  my $mode = shift;

  my $log = get_logger("PoolBot::System");
  my $sysConfig = getConfig('system');
  my $dHost = "export DOCKER_HOST=tcp://$sysConfig->{'dockerHost'}";

  notifyMatter("system setting pump service to $mode");

  if ($mode eq 'start') {
    $log->info("starting $sysConfig->{'pumpContainerName'} on $sysConfig->{'dockerHost'}");
    `$dHost; docker start $sysConfig->{'pumpContainerName'}`;
    return 1;
  } elsif ($mode eq 'stop') {
    $log->info("stopping $sysConfig->{'pumpContainerName'} on $sysConfig->{'dockerHost'}");
    `$dHost; docker stop $sysConfig->{'pumpContainerName'}`;
    return 0;
  }
}
