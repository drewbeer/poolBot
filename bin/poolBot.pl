#!/usr/bin/perl
# this is the api into jack, he's our leader, sky net can suck it.
#
use Mojolicious::Lite;
use Mojo::JSON qw(decode_json encode_json);
use DBI;
use strict;
use warnings;
use DateTime;
use LWP::Simple qw(!get);
use Log::Log4perl;
use Data::Dumper;
use HiPi::Device::GPIO;
use HiPi::Constant qw( :raspberry );
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
my $dbh = "";
my $bcm = "";
my $cron = "";
my $log = "";


## Functions
# startup
sub startup {
  my $self = shift;
  $self->log->info('poolBot Starting Up');

  # load up any saved schedules
  ## cron entry
  ##

  # should setup cron here too
  # my $entry = "0-59/5 * * * *";
  # $self->cron->add_entry($entry,\&cronDispatch,$pumpID,$program,$duration);
  # $self->cron->run(detach=>1,pid_file=>"/var/run/scheduler.pid");
}

# scheduler
sub runSchedule {
  my $args = shift;
  # $args->{id}
  # $args->{program}
  # $args->{duration}

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

# translates the relay status
sub powerNameMap {
  my ($value, $direction) = @_;
  # translate num to name
  if (!$direction) {
    my $name = "off";
    # set the value based on name instead
    if ($value) {
      $name = "on";
    }
    return $name;
  }
  # translate name to num
  if ($direction) {
    my $num = 0;
    # set the value based on name instead
    if ($value eq "on") {
      $num = 1;
    }
    return $num;
  }
  return 0;
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
    if($dbh){
        return $dbh;
    }else{
        $dbh = DBI->connect('DBI:mysql:database=poolBot;host=localhost','root','') or die $DBI::errstr;
        return $dbh;
    }
};

# Disconnect db connection
helper db_disconnect => sub {
    my $self = shift;
    $self->db->disconnect;
    $dbh = "";
};

# cron
helper cron => sub {
    if($cron){
        return $cron;
    }else{
        $cron = new Schedule::Cron(  sub { print "@_","\n" },
                                      file  => "poolBot.sched",
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
  my ($self, $relayName, $value) = @_;
  my $val = powerNameMap($value, 1);

  # get the relay id by name
  my $relayID = $relays->{$relayName};
  my $bcm  = HiPi::Device::GPIO->new();
  $bcm->export_pin( $relayID );
  my $pin  = $bcm->get_pin( $relayID );
  $pin->value($val);
  my $pinStatus = $pin->value();
  my $relayStatusName = powerNameMap($pinStatus, 0);
  return $relayStatusName;
};

# relay status
helper relayStatus => sub {
  my ($self, $relayName) = @_;
  my $relayID = $relays->{$relayName};
  if (!$relayID) {
    return 0;
  }
  my $bcm  = HiPi::Device::GPIO->new();
  $bcm->export_pin( $relayID );
  my $pin  = $bcm->get_pin( $relayID );
  my $pinStatus = $pin->value();
  my $relayStatusName = powerNameMap($pinStatus, 0);
  return $relayStatusName ;
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
get '/api/relay/set/:id/:value' => sub {
    my $self  = shift;
    my $relayID  = $self->stash('id');
    my $value  = $self->stash('value');
    if (!$relayID && !$value) {
      return $self->render(json => {error => "missing relay ID and value"});
    }
    my $relayStatus = $self->toggleRelay($relayID, $value);
    return $self->render(json => {relay => $relayID, value => $relayStatus});
};

# relay control
get '/api/relay/status/:id' => sub {
    my $self  = shift;
    my $relayID  = $self->stash('id');
    if (!$relayID) {
      return $self->render(json => {error => "missing relay ID"});
    }
    my $relayStatus = $self->relayStatus($relayID);
    return $self->render(json => {relay => $relayID, value => $relayStatus});
};

# Start the app
app->start;
