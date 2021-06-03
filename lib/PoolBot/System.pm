package PoolBot::System;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(heartbeat initSystem getSystemInfo systemShutdown runPool stopPool servicePumpController modeRun);

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use FindBin qw($Bin);
use PoolBot::Common;
use PoolBot::MatterMost;
use PoolBot::Pump;
use PoolBot::Relays;
use PoolBot::InfluxDB;
use PoolBot::MQTT;

# should replace runPool below, and you should only be able to fire off
# specific modes, and not like just the pump i guess.
# [modes]
# daily='pump:3:360,SCG'
# party='pump:3:480,SCG,Heater,Pool_Lights'
# spa='pump:2:300,SCG,Spa_Drain_Valve,Spa_Return_Valve,Heater'

sub modeRun {
  my $modeName = shift;
  my $durationOveride = shift;

  my $duration;
  my $pumpProgram;
  my @relays;
  my $pump = 1;

  my $log = get_logger("PoolBot::System");

  # gather all the mode details.
  my $config = getConfig('modes');
  my $modeDetails = $config->{$modeName};
  my (@modeObjects) = split(/\,/,$modeDetails);
  foreach my $mItem (@modeObjects) {
    if ($mItem =~ /^pump/) {
      $mItem =~ s/^pump\://;
      ($pumpProgram, $duration) = split(/\:/,$mItem);
    } else {
      push(@relays, $mItem);
    }
  }

  # if the duration is overridden.
  if ($durationOveride) {
    $duration = $durationOveride;
  }

  # how lets run the mode.
  my $relayNames = join(', ', @relays);
  my $message = "pool $modeName starting, running pump, and $relayNames for $duration minutes";
  $log->info($message);
  notifyMatter($message);

  # start the pump
  pumpRun($pump, $pumpProgram, $duration);

  # now turn on relays.
  foreach my $relay (@relays) {
    relaySet($relay, 1);
  }

  # publish the mode
  mqttPublishValue('Mode','Name', $modeName);
  mqttPublishValue('Mode','Duration', $duration);
  mqttPublishValue('Mode','Relays', $relayNames);

  return $message;
}

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
  my $log = get_logger("PoolBot::System");
  my $pump = 1;

  my $message = "stopping pool";
  $log->info($message);
  notifyMatter($message);
  pumpStop($pump);

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
    my $pumpCfg = getConfig('pump');
    my (@safetyItems) = split(/\,/,$pumpCfg->{'safety'});
    foreach my $sItem (@safetyItems) {
      my $name = $sItem;
      $name =~ s/\_/ /g;
      if ($relayStatus->{$sItem}) {
        $log->warn("pump may be off, turning off $name");
        notifyMatter("pump is $pumpStatus->{'currentrunning'}->{'mode'}, shutting down $name");
        relaySet($sItem, 0);
      }
    }

    # update mqtt
    mqttPublishValue('Mode','Name', 'Off');
    mqttPublishValue('Mode','Duration', 0);
    mqttPublishValue('Mode','Relays', '');
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
    mqttPublish('Pump', $pStats);
  }


  # do relays
  if ($data->{'relays'}) {
    foreach my $relay (keys %{$data->{'relays'}}) {
      my $relayStatus = ();
      my $tags = { location=>'pool', relay => $relay };
      $relayStatus->{'status'} = $data->{'relays'}->{$relay};
      writeInflux('pool_relays',$relayStatus, $tags);

      # publish relay data to mqtt
      my $mqtt = { switch => $data->{'relays'}->{$relay}, };
      $relay =~ s/_/ /g;
      mqttPublish($relay, $mqtt);
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
