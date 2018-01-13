#!/usr/bin/perl
# poolBot, a simple perl bot that runs a health check on the pool pump, and controls the relays

use strict;
use warnings;
use Mojolicious::Lite;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::Redis2;
use Try::Tiny;
use Config::Simple;
use Data::Dumper;

# load the Config
my $config = new Config::Simple('etc/poolBot.conf');
my $cfg = $config->vars();

# system settings
app->log->level($cfg->{'system.log_level'});
my $listenWebPort = $cfg->{'system.listen'};
my $gpioCMD = $cfg->{'system.gpioCMD'};

# pump pump
my $pumpUrl = $cfg->{'pump.url'};

# gpio relay map
my $relays = ();
$relays->{'valveIn'} = $cfg->{'relay.valveIn'};
$relays->{'ValveOut'} = $cfg->{'relay.ValveOut'};
$relays->{'salt'} = $cfg->{'relay.salt'};
$relays->{'heater'} = $cfg->{'relay.heater'};
$relays->{'lights'} = $cfg->{'relay.lights'};

app->log->info('poolBot Starting Up');

# GPIO setup
# make sure all pins are set to low
app->log->info('setting all relays to correct state');
foreach my $relayName (keys %{ $relays }) {
  `$gpioCMD mode $relays->{$relayName} out`;
}

# setup redis handler globally
my $redis = Mojo::Redis2->new;
$redis->set(term => "0");

### FUNCTIONS ###
# Startup function
# sub startup {
#   my $self = shift;
# }

# monitor fork for handling the health check and such
sub monFork {
  my ($monPID) = @_;
  app->log->info('monFork: Starting Health Check');
  while (!$redis->get("term")) {
    my $healthCheck = ();
    my $healthTime = timeStamp();

    $healthCheck->{'proc'}->{'name'} = "monFork";
    $healthCheck->{'proc'}->{'pid'} = $monPID;
    $healthCheck->{'proc'}->{'time'} = $healthTime->{'now'};

    # read all the relays
    foreach my $pin (keys %{ $relays }) {
      my $output = `$gpioCMD read $relays->{$pin}`;
      chomp $output;
      $healthCheck->{'relay'}->{$pin} = $output;
    }

    # read the pump
    my $pumpResponse = fetchUrl("$pumpUrl/pump", 1);
    if ($pumpResponse) {
      foreach my $pumpStat (keys %{ $pumpResponse->{1} }) {
        $healthCheck->{'pump'}->{$pumpStat} = $pumpResponse->{1}->{$pumpStat};
      }
    } else {
        $healthCheck->{'pump'} = 0;
    }

    my $statusMessage = "";
    # check if the pump is running, and what not.
    if ($healthCheck->{'pump'}->{'currentrunning'}->{'mode'} eq 'off') {
      # status log
      $statusMessage = qq(monFork: Pump is $healthCheck->{'pump'}->{'currentrunning'}->{'mode'});

      ## do the health check
      # turn off salt if its on
      if ($healthCheck->{'relay'}->{'salt'}) {
        app->log->warn('monFork: pump may be off, turning off salt');
        relayControl('salt', 'off');
      }
      # turn off heater if its on
      if ($healthCheck->{'relay'}->{'heater'}) {
        app->log->warn('monFork: pump may be off, turning off heater');
        relayControl('heater', 'off');
      }
    } else {
      # pump is running
      $statusMessage = qq(monFork: Pump is running $healthCheck->{'pump'}->{'currentrunning'}->{'mode'} at $healthCheck->{'pump'}->{'rpm'} using $healthCheck->{'pump'}->{'watts'} watts, with $healthCheck->{'pump'}->{'currentrunning'}->{'remainingduration'} minutes remaining);
    }

    # populate redis with whatever we have
    my $systemStatus = encode_json $healthCheck;
    $redis->set(systemStatus => $systemStatus);

    app->log->debug($statusMessage);
    sleep 5;
  }
  return;
}

## relay control ##
# toggle relays
sub relayControl {
  my ($relay, $value) = @_;
  if (!$relay || !$value) {
    return 0;
  }
  my $relayStatus;

  # before we allow toggles we should have some limits
  my $systemStatus = systemStatus();
  if (($systemStatus->{'pump'}->{'currentrunning'}->{'mode'} eq 'off') && ($value eq 'on')) {
    if ($relay eq 'heater' || $relay eq 'salt') {
      app->log->warn("can't enable $relay, pump is $systemStatus->{'pump'}->{'currentrunning'}->{'mode'}");
      return 0;
    }
  }

  # write the gpio value using a shell
  if ($value eq 'on') {
    `$gpioCMD write $relays->{$relay} 1`;
    $relayStatus = getRelayStatus($relay);
  } elsif ($value eq 'off') {
    `/usr/bin/gpio -g write $relays->{$relay} 0`;
    $relayStatus = getRelayStatus($relay);
  }
  app->log->debug("Relay $relays->{$relay} now $relayStatus");
  return $relayStatus;
}

# get the relay status
sub getRelayStatus {
  my ($relay) = @_;
  if (!$relay) {
    return 0;
  }
  my $relayStatusPretty = "off";
  # get relay status
  my $relayStatus = `$gpioCMD read $relays->{$relay}`;
  chomp $relayStatus;

  # if the relay is true then its "on"
  if ($relayStatus) {
    $relayStatusPretty = "on";
  }
  return $relayStatusPretty;
}

## utility code
# fetch the system status from redis and decode it
sub systemStatus {
  my $lastStatus = $redis->get("systemStatus");
  my $systemStatus = decode_json $lastStatus;
  return $systemStatus;
}

sub terminate {
  # turn off all the relays
  app->log->info("Shutting down Relays");
  foreach my $name (keys %{ $relays }) {
    my $relayStatus = relayControl($name,"off");
    app->log->info("Relay $name now $relayStatus");
  }
  exit;
}

# pass url, and if json should be parsed
sub fetchUrl {
  my ($url, $isJson) = @_;
  my $ua = Mojo::UserAgent->new();
  $ua->request_timeout(5);
  my $tx = $ua->get($url);
  my $res;
  try {
    $res = $tx->result;
  } catch {
    app->log->error("failed to fetch $url");
    $res = 0;
  };

  if ($res) {
    if ($res->is_success) {
      # if json is enabled
      my $decodedResponse = $res->body;
      if ($isJson) {
          $decodedResponse = decode_json($res->body);
      }
      return $decodedResponse;
    }

    # is error
    if ($res->is_error) {
      app->log->error("failed to fetch $url recieved $res->message");
      return 0;
    }
  }

  return 0;
};


sub timeStamp {
  # returns a timestamp for the file
  my $timestamp = ();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);

  $timestamp->{'file'} = sprintf ( "%04d%02d%02d-%02d.%02d.%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
  $timestamp->{'now'} = sprintf ( "%04d%02d%02d %02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
  $timestamp->{'nowDate'} = sprintf ( "%04d-%02d-%02d", $year+1900,$mon+1,$mday);

  return $timestamp;
}
### end of functions ###

# pump status
helper fetchPumpStatus => sub {
  my $self = shift;
  my $systemStatus = systemStatus();
  return $systemStatus->{'pump'};
};

# relay control
helper toggleRelay => sub {
  my ($self, $relay, $value) = @_;
  my $relayStatus = relayControl($relay, $value);
  return $relayStatus;
};

# relay status
helper relayStatus => sub {
  my ($self, $relay) = @_;
  my $relayStatus = getRelayStatus($relay);
  return $relayStatus ;
};

# monitoring fork
my $monFork = fork();
if ($monFork) {
  app->log->info("Starting monitor fork - $monFork");
  monFork($monFork);
}

if ($redis->get("term")) {
  exit;
}


# always runs
under sub {
my $c = shift;

# set some fork info
my $webTime = timeStamp();

my $webCheck = ();
$webCheck->{'proc'}->{'name'} = "webFork";
$webCheck->{'proc'}->{'time'} = $webTime->{'now'};

# store data in redis
my $webStatus = encode_json $webCheck;
$redis->set(webStatus => $webStatus);

return 1;
};


## relay API code ##
# relay control
get '/api/relay/set/:name/:value' => sub {
    my $self  = shift;
    my $relay  = $self->stash('name');
    my $value  = $self->stash('value');
    if (!$relay && !$value) {
      return $self->render(json => {error => "missing relay and value"});
    }
    my $relayStatus = $self->toggleRelay($relay, $value);
    return $self->render(json => {relay => $relay, value => $relayStatus});
};

# relay control
get '/api/relay/status/:name' => sub {
    my $self  = shift;
    my $relay  = $self->stash('name');
    if (!$relay) {
      return $self->render(json => {error => "missing relay"});
    }
    my $relayStatus = $self->relayStatus($relay);
    return $self->render(json => {relay => $relay, value => $relayStatus});
};

# exit command
get '/quit' => sub {
  my $self = shift;
  $self->redirect_to('/ping');
  $redis->set(term => "1");

  my $loop = Mojo::IOLoop->singleton;
  $loop->timer( 1 => sub { terminate(); exit; } );
  $loop->start unless $loop->is_running; # portability
};

# relay control
get '/ping' => sub {
    my $self  = shift;
    return $self->render(text => 'pong');
};

# Start the app
# web server listen
app->log->info('Starting Web Server');
app->config(poolBot => {listen => [$listenWebPort]});
app->start;
exit;
