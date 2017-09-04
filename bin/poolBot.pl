#!/usr/bin/perl
# poolBot, a perl based web api to talk to different things that affect my pool
#
## TODO:
# health check (salt cannot run without the pump running) should be thread
# scheduling
# slack output
# web status in json
# settings page
#
#
use strict;
use warnings;
use Mojolicious::Lite;
use Mojo::JSON qw(decode_json encode_json);
use DateTime;
use RocksDB;
use Data::Dumper;
use Schedule::Cron;
use Try::Tiny;

# debug
app->log->level('debug');

my $pumpUrl = "http://10.42.2.19:3000";
my $rachioKey = "4236ff47-df71-4c5d-8520-c4fa9236944d";
my $listenWebPort = 'http://*:3000';
my $dbLocation = '../etc/poolBot.db';

# gpio stuff
my $gpioCMD = '/usr/bin/gpio -g';

# gpio relay map
my $relays = ();
$relays->{'valveIn'} = 5;
$relays->{'ValveOut'} = 4;
$relays->{'salt'} = 16;
$relays->{'heater'} = 12;
$relays->{'spa'} = 18;

# # Check title in the background every 10 seconds
# my $title = 'Got no title yet.';
# Mojo::IOLoop->recurring(10 => sub {
#   app->ua->get('http://mojolicious.org' => sub {
#     my ($ua, $tx) = @_;
#     $title = $tx->result->dom->at('title')->text;
#   });
# });

my $poolBot = ();
my $cron="";

# setup the db
my $db = RocksDB->new($dbLocation, { create_if_missing => 1 });
$db->put('term', 0);

# Startup function
sub startup {
  my $self = shift;
  app->log->debug('poolBot Starting Up');

  # clear the rocksDB term status

  # GPIO setup
  # make sure all pins are set to low
  app->log->debug('Exporting GPIO pins');
  foreach my $pin (keys %{ $relays }) {
    `$gpioCMD export $relays->{$pin} low`;
  }

  # lets pull the default schedule for cron
  app->log->debug('Retrieving stored crontab');
  my $cronJSON = $self->db->get('crontab');

  if ($cronJSON)  {
    my $crontab = decode_json $cronJSON;
    # load the cron
    foreach my $cron ( %{ $crontab }) {
      # $self->cron->add_entry($cron->{'datetime'},\&cronScheduler,$self,$cron->{'mode'},$cron->{'duration'});
    }
    # run the cron and detach
    # $self->cron->run(detach=>1,pid_file=>"../log/scheduler.pid");
  }

  # now we should startup any threads for background stuff

}

# cron details, aka modes
# when generating cron, it should have two entries.
# 1. general crontab entry, that is when, and what and how long to run something for
# 2. details about the specific cron to run
#   a. pump only, pump and salt, pump and heater, so on.
#   b. how fast the pump should run
#   c. how high to let the temp get to on heat functions
#
# modes should have a key prefix, like
# 1. mode_pump_only
# 2. mode_heat
# 3. mode_normal_high
# 4. mode_normal_med
# 5. mode_normal_low
sub cronScheduler {
  my $args = shift;
  my $self = $args->{self};
  my $mode = $args->{mode};
  my $duration = $args->{duration};

  # lets get the specific details of this program
  my $cronModes = $self->db->get("$mode");

}

# generate timestamp data
sub timeStamp {
	my $self = shift;
	# returns a timestamp for the file
	my $timestamp = ();
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	$timestamp->{'file'} = sprintf ( "%04d%02d%02d-%02d.%02d.%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
	$timestamp->{'now'} = sprintf ( "%04d%02d%02d %02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
	$timestamp->{'nowMinute'} = sprintf ( "%02d", $min);

	return $timestamp;
};

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
    app->log->debug("failed to fetch $url");
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
      app->log->debug("failed to fetch $url recieved $res->message");
      return 0;
    }
  }

  return 0;
};

# fetch the rachio url
sub fetchRachioUrl {
  my ($url, $value) = @_;
  my $curlUrl = "curl -X PUT -H 'Content-Type: application/json' -H 'Authorization: Bearer 'rachioKey' -d '$value' $url";
  my $response = `$curlUrl`;
  if (!$response) {
    return 0;
  }
  my $decodedResponse = decode_json($response);
  return $decodedResponse;
};

sub relayControl {
  my ($relay, $value) = @_;
  if (!$relay || !$value) {
    return 0;
  }
  my $relayStatus;

  # write the gpio value using a shell
  if ($value eq 'on') {
    my $command = "$gpioCMD write $relays->{$relay} 1";
    app->log->debug("gpio command: $command");
    `$command`;
    $relayStatus = relayStatus($relay);
  } elsif ($value eq 'off') {
    `/usr/bin/gpio -g write $relays->{$relay} 0`;
    $relayStatus = relayStatus($relay);
  }
  return $relayStatus;
}

sub relayStatus {
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

# Create db connection if needed
helper db => sub {
    if ($db) {
      return $db;
    } else {
      $db = RocksDB->new($dbLocation, { create_if_missing => 1 });
      return $db;
    }
};

# cron
helper cron => sub {
  if ($cron) {
    return $cron;
  } else {
    $cron = new Schedule::Cron(  sub { print "@_","\n" },
                                  file  => "../etc/poolBot.sched",
                                  eval  => 1);
    return $cron;
  }
};

# rachio helper
#
# start zone 8
# value: '{ "id" : "c1ec26b1-f514-44d1-bcec-bf46c7bea5c8", "duration" : 60 }'
# url: 'https://api.rach.io/1/public/zone/start'
#
helper startPoolFill => sub {
  my ($self, $duration) = @_;
  my $rachioValue = "{ 'id' : 'c1ec26b1-f514-44d1-bcec-bf46c7bea5c8', 'duration' : $duration }";
  my $rachioStartUrl = 'https://api.rach.io/1/public/zone/start';
  my $rachioResponse = fetchRachioUrl($rachioStartUrl, $rachioStartUrl);
  if ($rachioResponse) {
    print Dumper($rachioResponse);
  }
  return $rachioResponse;
};

# # stop all water
# value '{ "id" : "72c57cc8-ce7e-4faa-a99a-1740aa1a2431" }'
# url 'https://api.rach.io/1/public/device/stop_water'
helper stopPoolFill => sub {
  my ($self) = @_;
  my $rachioValue = '{ "id" : "72c57cc8-ce7e-4faa-a99a-1740aa1a2431" }';
  my $rachioStopUrl = 'https://api.rach.io/1/public/device/stop_water';
  my $rachioResponse = fetchRachioUrl($rachioStopUrl, $rachioValue);
  if ($rachioResponse) {
    print Dumper($rachioResponse);
  }
  return $rachioResponse;
};

# pump status
helper fetchPumpStatus => sub {
  my $self = shift;
  my $pumpStatus = ();
  # fetch the pump status and only one since thats all we have
  my $pumpStatusUrl = "$pumpUrl/pump";
  my $pumpResponse = fetchUrl($pumpStatusUrl, 1);
  if ($pumpResponse) {
    foreach my $pumpStat (keys %{ $pumpResponse->[1] }) {
      $pumpStatus->{'1'}->{$pumpStat} = $pumpResponse->[1]->{$pumpStat};
    }
  }
  return $pumpStatus;
};

# pump run
helper setPumpRun => sub {
  my ($self, $pumpID, $program, $duration) = @_;
  # fetch the pump status and only one since thats all we have
  my $pumpRunCMD = "$pumpUrl/pumpCommand/run/pump/$pumpID/program/$program/duration/$duration";
  my $pumpResponse = fetchUrl($pumpRunCMD,1);
  return $pumpResponse;
};

# pump power
helper setPumpPower => sub {
  my ($self, $pumpID, $value) = @_;
  my $pumpRunCMD = "$pumpUrl/pumpCommand/$value/pump/$pumpID";
  my $pumpResponse = fetchUrl($pumpRunCMD,1);
  return $pumpResponse;
};

# pump status
helper setPumpProgram => sub {
  my ($self, $pumpID, $program, $rpm) = @_;
  # fetch the pump status and only one since thats all we have
  my $pumpProgramCMD = "$pumpUrl/pumpCommand/save/pump/$pumpID/program/$program/rpm/$rpm";
  my $pumpResponse = fetchUrl($pumpProgramCMD,1);
  return $pumpResponse;
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
  my $relayStatus = relayStatus($relay);
  return $relayStatus ;
};


## Api Routes
# # Always check auth token!  Here we validate that every API request
# # has a valid token
# under sub {
#     my $self  = shift;
#     my $token   = $self->param('token');
#
#     if (!$token) {
#       $self->render(text => "Access Token Required, goodbye.");
#       $self->db_disconnect;
#       return;
#     }
#
#     my $SQL = "select name from authTokens where token = '$token' and active = 1";
#     my $cursor = $self->db->prepare($SQL);
#     $cursor->execute;
#     my @name = $cursor->fetchrow;
#     $cursor->finish;
#
#     if($name[0]){
#         return 1;
#     }else{
#         $self->render(text => "I'm sorry, Dave. I'm afraid I can't do that.");
#         $self->db_disconnect;
#         return;
#     }
# };

# monitoring fork
my $monFork = fork();

# health check
if ($monFork) { # If this is the child thread
  my $term = $db->get('term');
  app->log->debug('Starting Health Check | $term');
  while ($term == 0) {
    app->log->debug("Health check running | $term");
    my $healthCheck = ();
    # read all the relays
    foreach my $pin (keys %{ $relays }) {
      my $output = `$gpioCMD read $relays->{$pin}`;
      chomp $output;
      $healthCheck->{'relay'}->{$pin} = $output;
    }

    # read the pump
    my $pumpResponse = fetchUrl("$pumpUrl/pump", 1);
    if ($pumpResponse) {
      foreach my $pumpStat (keys %{ $pumpResponse->[1] }) {
        $healthCheck->{'pump'}->{$pumpStat} = $pumpResponse->[1]->{$pumpStat};
      }
    } else {
      $healthCheck->{'pump'}->{'rpm'} = 0;
    }

    # if pump is not running, and salt is turn it off
    if ($healthCheck->{'relay'}->{'salt'} && !$healthCheck->{'pump'}->{'rpm'}) {
      app->log->debug('health: Pump has been turned off, but salt is still on, turning off');
      relayControl('salt', 'off');
    }

    sleep 10;
    $term = $db->get('term');
  }
  exit;
}

# webFork
my $webFork = fork();

# web fork module
if ($webFork) {
  # Power from rainforest
  get '/api/power/incoming' => sub {
      my $self  = shift;
      my $pumpID  = $self->stash('id');
      if (!$pumpID) {
        return $self->render(json => {error => "missing pump number"});
      }
      my $pumpStatus = $self->fetchPumpStatus($pumpID);
      if (!$pumpStatus) {
        return $self->render(json => {error => "pump controller unavailable"});
      }
      return $self->render(json => {name => $pumpStatus->{$pumpID}->{'name'}, watts => $pumpStatus->{$pumpID}->{'watts'}, rpm => $pumpStatus->{$pumpID}->{'rpm'}, run => $pumpStatus->{$pumpID}->{'run'}, program1rpm => $pumpStatus->{$pumpID}->{'program1rpm'}, program1rpm => $pumpStatus->{$pumpID}->{'program1rpm'}, program2rpm => $pumpStatus->{$pumpID}->{'program2rpm'}, program3rpm => $pumpStatus->{$pumpID}->{'program3rpm'}, program4rpm => $pumpStatus->{$pumpID}->{'program4rpm'},programRemaining => $pumpStatus->{$pumpID}->{'currentrunning'}->{'remainingduration'}, programRunning => $pumpStatus->{$pumpID}->{'currentrunning'}->{'value'}, programMode => $pumpStatus->{$pumpID}->{'currentrunning'}->{'mode'}});
  };

  # pump status
  get '/api/pump/status/:id' => sub {
      my $self  = shift;
      my $pumpID  = $self->stash('id');
      if (!$pumpID) {
        return $self->render(json => {error => "missing pump number"});
      }
      my $pumpStatus = $self->fetchPumpStatus($pumpID);
      if (!$pumpStatus) {
        return $self->render(json => {error => "pump controller unavailable"});
      }
      return $self->render(json => {name => $pumpStatus->{$pumpID}->{'name'}, watts => $pumpStatus->{$pumpID}->{'watts'}, rpm => $pumpStatus->{$pumpID}->{'rpm'}, run => $pumpStatus->{$pumpID}->{'run'}, program1rpm => $pumpStatus->{$pumpID}->{'program1rpm'}, program1rpm => $pumpStatus->{$pumpID}->{'program1rpm'}, program2rpm => $pumpStatus->{$pumpID}->{'program2rpm'}, program3rpm => $pumpStatus->{$pumpID}->{'program3rpm'}, program4rpm => $pumpStatus->{$pumpID}->{'program4rpm'},programRemaining => $pumpStatus->{$pumpID}->{'currentrunning'}->{'remainingduration'}, programRunning => $pumpStatus->{$pumpID}->{'currentrunning'}->{'value'}, programMode => $pumpStatus->{$pumpID}->{'currentrunning'}->{'mode'}});
  };

  # set the pump program.
  get '/api/pump/set/:id/:program/:rpm' => sub {
      my $self  = shift;
      my $pumpID  = $self->stash('id');
      my $program  = $self->stash('program');
      my $rpm  = $self->stash('rpm');
      if (!$rpm && !$program && !$pumpID) {
        return $self->render(json => {error => "missing fields"});
      }
      my $pumpResponse = $self->setPumpProgram($pumpID, $program, $rpm);
      if (!$pumpResponse) {
        return $self->render(json => {error => "pump controller unavailable"});
      }
      return $self->render(json => {pump => $pumpResponse->{'pump'}, program => $pumpResponse->{'program'}, rpm => $pumpResponse->{'speed'}});
  };

  # set the pump run with duration
  get '/api/pump/run/:id/:program/:duration' => sub {
      my $self  = shift;
      my $pumpID  = $self->stash('id');
      my $program  = $self->stash('program');
      my $duration  = $self->stash('duration');
      if (!$duration && !$program && !$pumpID) {
        return $self->render(json => {error => "missing fields"});
      }
      my $pumpResponse = $self->setPumpRun($pumpID, $program, $duration);
      if (!$pumpResponse) {
        return $self->render(json => {error => "pump controller unavailable"});
      }
      return $self->render(json => {pump => $pumpResponse->{'pump'}, program => $pumpResponse->{'program'}, duration => $pumpResponse->{'duration'}});
  };

  # turn on pool fill
  get '/api/pool/water/on/:duration' => sub {
      my $self  = shift;
      my $duration  = $self->stash('duration');
      if (!$duration) {
        return $self->render(json => {error => "missing duration"});
      }
      my $poolFillResponse = $self->startPoolFill($duration);
      if (!$poolFillResponse) {
        return $self->render(json => {error => "rachio not working"});
      }
      return $self->render(json => {pump => $poolFillResponse->{'duration'}, power => $poolFillResponse->{'remaining'}});
  };

  # turn off pool fill
  get '/api/pool/water/off' => sub {
      my $self  = shift;
      my $poolFillResponse = $self->stopPoolFill();
      if (!$poolFillResponse) {
        return $self->render(json => {error => "rachio not working"});
      }
      return $self->render(json => {pump => $poolFillResponse->{'status'}});
  };

  # pump on or off
  get '/api/pump/power/:id/:value' => sub {
      my $self  = shift;
      my $pumpID  = $self->stash('id');
      my $value  = $self->stash('value');
      if (!$pumpID && !$value) {
        return $self->render(json => {error => "missing fields"});
      }
      my $pumpResponse = $self->setPumpPower($pumpID, $value);
      if (!$pumpResponse) {
        return $self->render(json => {error => "pump controller unavailable"});
      }
      return $self->render(json => {pump => $pumpResponse->{'pump'}, power => $pumpResponse->{'power'}});
  };

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
    $self->redirect_to('http://google.com');
    # update the rocksdb to terminate all threads
    $self->db->put('term', 1);

    my $loop = Mojo::IOLoop->singleton;
    $loop->timer( 1 => sub { exit } );
    $loop->start unless $loop->is_running; # portability
  };

  # Start the app
  # web server listen
  app->log->debug('Starting Web Server');
  app->config(poolBot => {listen => [$listenWebPort]});
  app->start;
} # end of web fork
