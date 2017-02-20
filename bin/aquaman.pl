#!/usr/bin/perl
# this is the api into jack, he's our leader, sky net can suck it.
#
use Mojolicious::Lite;
use Mojo::JSON qw(decode_json encode_json);
use DBI;
use strict;
use warnings;
use DateTime;
use Date::Calc qw/Delta_Days/;
use LWP::Simple qw(!get);
use Log::Log4perl;
use Data::Dumper;
use HiPi::BCM2835;
use HiPi::Utils;

my $pumpUrl = "http://10.42.2.19:3000";

# log file setup
Log::Log4perl->init("../etc/aquaman.log.conf");

# logging setup
my $log = Log::Log4perl->get_logger("aquaman");

$log->info("Starting AquaMan");

# listen on code
app->config(aquaman => {listen => ['http://*:3000']});

# Global handle for db connections
my $dbh = "";
my $bcm = "";

# Helpers for the db

# # Create db connection if needed
# helper db => sub {
#     if($dbh){
#         return $dbh;
#     }else{
#         $dbh = DBI->connect('DBI:mysql:database=aquaman;host=localhost','root','') or die $DBI::errstr;
#         return $dbh;
#     }
# };
#
# # Disconnect db connection
# helper db_disconnect => sub {
#     my $self = shift;
#     $self->db->disconnect;
#     $dbh = "";
# };

helper bmc => sub {
  my($bmcUser, $bmcGroup) = ('pi', 'pi');
  if ($bcm) {
      return $bcm;
  } else {
      $bcm = HiPi::BCM2835->new();
      HiPi::Utils::drop_permissions_name($bmcUser, $bmcGroup);
      return $bcm;
  }
};

# my $pin = 18;
# my $level = $bcm->gpio_lev( $pin );
#
# print "level is $level\n";
#
# # high
# #$bcm->gpio_set( $pin );
# # low
# $bcm->gpio_clr( $pin );


sub fetchUrl {
  my ($self, $url) = @_;
  my $response = LWP::Simple::get($url);
  return $response;
};

helper fetchPumpStatus => sub {
  my $self = shift;
  my $pumpStatus = ();
  # fetch the pump status and only one since thats all we have
  my $pumpStatusUrl = "$pumpUrl/pump";
  my $pumpResponse = LWP::Simple::get($pumpStatusUrl);
  if ($pumpResponse) {
    my $pumpStatusData = decode_json($pumpResponse);
    foreach my $pumpStat (keys %{ $pumpStatusData->[1] }) {
      $pumpStatus->{'1'}->{$pumpStat} = $pumpStatusData->[1]->{$pumpStat};
    }
  }
  return $pumpStatus;
};

helper toggleRelay => sub {
  my ($self, $relay, $value) = @_;
  if ($value > 1) {
    return 0;
  }
  if ($value) {
    $self->bcm->gpio_set( $relay );
  } else {
    $self->bcm->gpio_clr( $relay );
  }
  my $relayStatus = $self->bcm->gpio_lev( $relay );
  return $relayStatus;
};

helper relayStatus => sub {
  my ($self, $relay) = @_;
  if (!$relay) {
    return 0;
  }
  my $relayStatus = $self->bcm->gpio_lev( $relay );
  return $relayStatus;
};

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


## Blacklist API code ##

# pump status
get '/api/pump/status/:id' => sub {
    my $self  = shift;
    my $pumpID  = $self->stash('id');
    my $pumpStatus = $self->fetchPumpStatus($pumpID);
    return $self->render(json => {name => $pumpStatus->{$pumpID}->{'name'}, watts => $pumpStatus->{$pumpID}->{'watts'}, rpm => $pumpStatus->{$pumpID}->{'rpm'}, run => $pumpStatus->{$pumpID}->{'run'}, program1rpm => $pumpStatus->{$pumpID}->{'program1rpm'}, program1rpm => $pumpStatus->{$pumpID}->{'program1rpm'}, program2rpm => $pumpStatus->{$pumpID}->{'program2rpm'}, program3rpm => $pumpStatus->{$pumpID}->{'program3rpm'}, program4rpm => $pumpStatus->{$pumpID}->{'program4rpm'},programRemaining => $pumpStatus->{$pumpID}->{'currentrunning'}->{'remainingduration'}, programRunning => $pumpStatus->{$pumpID}->{'currentrunning'}->{'value'}, programMode => $pumpStatus->{$pumpID}->{'currentrunning'}->{'mode'}});
};

# relay control
get '/api/relay/set/:id/:value' => sub {
    my $self  = shift;
    my $relayID  = $self->stash('id');
    my $value  = $self->stash('value');
    my $relayStatus = $self->toggleRelay($relayID, $value);
    return $self->render(json => {relay => $relayID, value => $relayStatus});
};

# relay control
get '/api/relay/status/:id' => sub {
    my $self  = shift;
    my $relayID  = $self->stash('id');
    my $relayStatus = $self->relayStatus($relayID);
    return $self->render(json => {relay => $relayID, value => $relayStatus});
};

# Start the app
app->start;
