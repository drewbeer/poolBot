package PoolBot::Relays;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(relaySet relayGet showRelays initRelays relayShutdown lightCycle);

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use FindBin qw($Bin);
use PoolBot::Common;
use PoolBot::MQTT;

my $log = get_logger("PoolBot::Relays");

## relay control ##
sub relaySet {
  my $relay = shift;
  my $value = shift;

  $log->info("setting $relay to $value");
  my $relays = getConfig('relays');
  my $gpioCMD = getGPIO();

  unless ($relay || defined $value) {
    $log->error("no relay specified");
    return 0;
  }

  `$gpioCMD write $relays->{$relay} $value`;
  # we keep this here because sometimes it doesn't turn off fast enough
  sleep 1;
  my $relayStatus = relayGet($relay);
  $log->debug("relay $relay now $relayStatus");

  # push the change to mqtt rigth away
  $relay =~ s/_/ /g;
  mqttPublishValue($relay,'switch', $relayStatus);

  return $relayStatus;
}

# get the relay status
sub relayGet {
  my ($relay) = shift;
  if (!$relay) {
    return 0;
  }

  my $relays = getConfig('relays');
  my $gpioCMD = getGPIO();

  # get relay status
  my $relayStatus = `$gpioCMD read $relays->{$relay}`;
  chomp $relayStatus;
  return $relayStatus;
}

sub showRelays {

  my $relays = getConfig('relays');
  my $gpioCMD = getGPIO();

  # read all the relays
  my $status = ();
  foreach my $name (keys %{ $relays }) {
    my $output = `$gpioCMD read $relays->{$name}`;
    chomp $output;
    $status->{$name} = $output;
  }
  return $status;
}

sub initRelays {
  $log->debug('initializing relays');
  my $relays = getConfig('relays');
  my $gpioCMD = getGPIO();

  foreach my $relayName (keys %{ $relays }) {
    `$gpioCMD mode $relays->{$relayName} out`;
  }
  return;
}

sub relayShutdown {
  my $relays = getConfig('relays');
  # turn off all the relays
  $log->info("shutting down all relays");
  foreach my $name (keys %{ $relays }) {
    my $relayStatus = relaySet($name,0);
    $log->info("relay $name now $relayStatus");
  }
}

# should be responsible for changing the light colors.
sub lightCycle {
  my $name = 'poolLights';

  # cycle the relay
  relaySet($name, 0);
  my $status = relaySet($name, 1);
  return $status;
}

sub getGPIO {
  my $gpioCfg = getConfig('system');
  my ($cmd, $flag) = split(/\s+/, $gpioCfg->{'gpioCMD'});
  if (-f $cmd) {
    return $gpioCfg->{'gpioCMD'};
  } else {
    $log->error("cannot find gpio command: $gpioCfg->{'gpioCMD'}");
    return 0;
  }
}
