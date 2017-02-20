#!/Users/drew/perl5/perlbrew/perls/perl-5.21.11/bin/perl
# this is the api into jack, he's our leader, sky net can suck it.
#
use strict;
use warnings;
use LWP::Simple qw(!get);
use Data::Dumper;
use JSON;

my $pumpUrl = "http://10.42.2.19:3000";

my $pumpStatus = ();
# fetch the pump status and only one since thats all we have
my $pumpStatusUrl = "$pumpUrl/pumpCommand/run/pump/1/program/1/duration/500";
my $pumpResponse = LWP::Simple::get($pumpStatusUrl);
if ($pumpResponse) {
  my $pumpStatusData = JSON->new->utf8(1)->decode($pumpResponse);
  print Dumper($pumpStatusData);

  # foreach my $pumpStat (keys %{ $pumpStatusData->[1] }) {
  #   $pumpStatus->{'pump'}->{$pumpStat} = $pumpStatusData->[1]->{$pumpStat};
  # }
}

# print Dumper($pumpStatus);
