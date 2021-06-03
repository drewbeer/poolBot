package PoolBot::MQTT;


require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(mqttPublish mqttPublishValue);

use strict;
use warnings;
use Net::MQTT::Simple;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Log::Log4perl qw(get_logger);
use PoolBot::Common;

my $log = get_logger("PoolBot::MQTT");

# update redis with list sorted by status and id
sub mqttPublish {
  my $subTopic = shift;
  my $data = shift;
  my $mqttConfig = getConfig('mqtt');
  unless ($mqttConfig->{'host'}) {
    return;
  }
  my $mqtt = Net::MQTT::Simple->new($mqttConfig->{'host'});

  foreach my $field (keys %{$data}) {
    my $topic = "$mqttConfig->{'topic'}/$subTopic/$field";
    $log->debug("mqtt post for $field with $data->{$field} to $topic");
    $mqtt->retain( $topic => $data->{$field});
  }
  $mqtt->disconnect;
  return;
}


sub mqttPublishValue {
  my $subTopic = shift;
  my $field = shift;
  my $value = shift;

  my $mqttConfig = getConfig('mqtt');
  unless ($mqttConfig->{'host'}) {
    return;
  }
  my $mqtt = Net::MQTT::Simple->new($mqttConfig->{'host'});

  my $topic = "$mqttConfig->{'topic'}/$subTopic/$field";
  $mqtt->retain( $topic => $value);
  $log->debug("mqtt post for $field with $value to $topic");

  $mqtt->disconnect;
  return;
}
