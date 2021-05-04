package PoolBot::Common;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(getConfig int2float timeStamp getURL postURL postInflux);

use strict;
use warnings;
use Config::Simple;
use Log::Log4perl qw(get_logger);
use FindBin qw($Bin);
use HTTP::Tiny;

my $log = get_logger("PoolBot::Common");

# get config function
sub getConfig {
  my $arg = shift;

  # first validate the config
  my $cfg = new Config::Simple("$Bin/../etc/settings.conf");

  # get a specific block
  if ($arg) {
    my $config = $cfg->get_block($arg);
    return $config;
  }

  my $config = $cfg->vars();
  unless ($config) {
    return 0;
  }

  return $config;
};

sub getURL {
  my $url = shift;
  my $log = get_logger("HTTP::Tiny");

  my $http = HTTP::Tiny->new( timeout => 5 );
  my $response = $http->get($url);

  if ( $response->{success} ) {
    return $response->{content};
  }
  return 0;
}

# post data to influx
sub postInflux {
  my $data = shift;
  my $influxConfig = getConfig('influxDB');

  unless ($influxConfig->{'host'} && $influxConfig->{'token'}) {
    return
  }

  my $url = "http://$influxConfig->{'host'}:$influxConfig->{'port'}/api/v2/write?org=$influxConfig->{'org'}&bucket=$influxConfig->{'db'}";
  my %headers = (
    "Content-Type" => "application/json",
    "Authorization" => sprintf 'Token %s', $influxConfig->{'token'});

  my $response = HTTP::Tiny->new->request('POST',$url, { headers => \%headers, content=>$data });
  unless ($response->{'status'} =~ /2\d+/) {
    print "bad\n";
    print Dumper($response);
  }
}

sub postURL {
  my $url = shift;
  my $data = shift;
  my $log = get_logger("HTTP::Tiny");

  my $http = HTTP::Tiny->new( timeout => 5 );
  my $response = $http->post($url, {content => $data});

  if ( $response->{success} ) {
    return $response->{content};
  }
  $log->error("failed request: $response->{content}");
  use Data::Dumper;
  print Dumper($response);
  return 0;
}


sub int2float {
  my $var = shift;

  # if its blank set it to 0
  unless ($var) {
    $var = '0.00';
    return $var;
  }

  # if its not a number then....
  unless ($var =~ /^\d+/) {
    $var = '0.00';
    return $var;
  }

  # if its not decimal add it
  unless ($var =~ /^\d+\.\d+/) {
    $var .= '.00';
    return $var;
  }

  return $var;
}

sub timeStamp {
  my $targetTime = shift;
  my $nowTime = time;

  if ($targetTime) {
    $nowTime = $targetTime;
  }

  # returns a timestamp for the file
  my $timestamp = ();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($nowTime);
  $year = $year+1900;
  $mon = $mon+1;

  # various time usages
  $timestamp->{'file'} = sprintf ( "%04d%02d%02d-%02d.%02d.%02d", $year,$mon,$mday,$hour,$min,$sec);
  $timestamp->{'pretty'} = sprintf ( "%04d%02d%02d %02d:%02d:%02d", $year,$mon,$mday,$hour,$min,$sec);
  $timestamp->{'clean'} = sprintf ( "%04d%02d%02d-%02d:%02d:%02d", $year,$mon,$mday,$hour,$min,$sec);
  $timestamp->{'date'} = sprintf ( "%04d%02d%02d", $year,$mon,$mday);
  $timestamp->{'minute'} = sprintf ( "%02d", $min);
  $timestamp->{'hour'} = sprintf ( "%02d", $hour);

  # epoc
  $timestamp->{'epoc'} = $nowTime;

  # return our ref
    return $timestamp;
}
1;
