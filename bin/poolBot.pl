#!/usr/bin/perl
# this is the api into jack, he's our leader, sky net can suck it.
#
use Mojolicious::Lite;
use Mojo::JSON qw(decode_json encode_json);
use strict;
use warnings;
use DateTime;
use LWP::Simple qw(!get);
use RocksDB;
use Log::Log4perl;
use Data::Dumper;
use Schedule::Cron;

my $relays = ();
my $pumpUrl = "http://10.42.2.19:3000";
my $rachioKey = "4236ff47-df71-4c5d-8520-c4fa9236944d";

# relay map
$relays->{'valveIn'} = 5;
$relays->{'ValveOut'} = 4;
$relays->{'salt'} = 16;
$relays->{'heater'} = 12;
$relays->{'spa'} = 18;

# database scheduling

# we should load up the cron for any schedules in memory and start them before the api kicks off

# web server listen
app->config(poolBot => {listen => ['http://*:3000']});

# Global handle for db connections
my $db = "";
my $cron = "";
my $log = "";


## Functions
# Startup function
sub startup {
  my $self = shift;
  $self->log->info('poolBot Starting Up');

  # GPIO setup
  # make sure all pins are set to low
  $self->log->info('Exporting GPIO pins');
  foreach my $pin (keys %{ $relays }) {
    `gpio export $pin low`;
  }

  # lets pull the default schedule for cron
  $self->log->info('Retrieving stored crontab');
  my $cronJSON = $self->db->get('crontab');

  if ($cronJSON)  {
    my $crontab = decode_json $cronJSON;
    # load the cron
    foreach my $cron ( %{ $crontab }) {
      # $self->cron->add_entry($cron->{'datetime'},\&runSchedule,$cron->{'pump'},$cron->{'program'},$cron->{'duration'});
    }
    # run the cron and detach
    # $self->cron->run(detach=>1,pid_file=>"../log/scheduler.pid");
  }

}

# scheduler
sub runSchedule {
  my $args = shift;
  my $pump = $args->{pump};
  my $program = $args->{program};
  my $duration = $args->{duration};

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
  my $response = LWP::Simple::get($url);
  if (!$response) {
    return 0;
  }
  my $decodedResponse = decode_json($response);
  return $decodedResponse;
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
  my ($self, $relay, $value) = @_;
  if (!$relay || !$value) {
    return 0;
  }
  my $relayStatus;

  # write the gpio value using a shell
  if ($value eq 'on') {
    my $command = "/usr/bin/gpio export $relays->{$relay} high";
    $self->log->info("gpio command: $command");
    `$command`;
    $relayStatus = relayStatus($relay);
  } elsif ($value eq 'off') {
    `/usr/bin/gpio export $relays->{$relay} low`;
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
  my $relayStatus = `/usr/bin/gpio read $relays->{$relay}`;
  chomp $relayStatus;

  # if the relay is true then its "on"
  if ($relayStatus) {
    $relayStatusPretty = "on";
  }
  return $relayStatusPretty;
}

# $cron->add_entry("0-40/5,55 3,22 * Jan-Nov Fri", {
#   sub  => \&runSchedule,
#     args => [ {
#       id   => 1,
#       program => 2,
#       duration => 300
#     } ],
#    eval => 0 }
# );

## Helpers
helper log => sub {
    if ($log) {
      return $log;
    } else {
      # log file setup
      Log::Log4perl->init("../etc/poolBot.log.conf");

      # logging setup
      $log = Log::Log4perl->get_logger("poolBot");
      return $log;
    }
};

# Create db connection if needed
helper db => sub {
    if($db){
        return $db;
    }else{
        $db = RocksDB->new('../etc/poolBot.db', { create_if_missing => 1 });
        return $db;
    }
};

# cron
helper cron => sub {
    if($cron){
        return $cron;
    }else{
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
  my $pumpResponse = fetchUrl($pumpStatusUrl);
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
  my $pumpResponse = fetchUrl($pumpRunCMD);
  return $pumpResponse;
};

# pump power
helper setPumpPower => sub {
  my ($self, $pumpID, $value) = @_;
  my $pumpRunCMD = "$pumpUrl/pumpCommand/$value/pump/$pumpID";
  my $pumpResponse = fetchUrl($pumpRunCMD);
  return $pumpResponse;
};

# pump status
helper setPumpProgram => sub {
  my ($self, $pumpID, $program, $rpm) = @_;
  # fetch the pump status and only one since thats all we have
  my $pumpProgramCMD = "$pumpUrl/pumpCommand/save/pump/$pumpID/program/$program/rpm/$rpm";
  my $pumpResponse = fetchUrl($pumpProgramCMD);
  return $pumpResponse;
};

# relay control
helper toggleRelay => sub {
  my ($self, $relay, $value) = @_;
  $self->log->info("Toggling $relay to $value");
  my $relayStatus = relayControl($self, $relay, $value);
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

# Start the app
app->start;
