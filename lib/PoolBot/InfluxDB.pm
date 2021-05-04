package PoolBot::InfluxDB;


require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(writeInflux);

use strict;
use warnings;
use InfluxDB::LineProtocol qw(data2line);
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Log::Log4perl qw(get_logger);
use PoolBot::Common;

my $log = get_logger("PoolBot::Influx");

# update redis with list sorted by status and id
sub writeInflux {
  my $source = shift;
  my $stats = shift;
  my $tags = shift;

  $log->debug("recording stats for $source in influxDB");
  my $nodeLine = data2line($source, $stats, $tags);
  $log->debug("idb: $nodeLine");
  postInflux($nodeLine);
}
