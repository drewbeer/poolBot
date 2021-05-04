package PoolBot::MatterMost;


require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(notifyMatter);

use strict;
use warnings;
use JSON;
use FindBin qw($Bin $Script);
use lib "$Bin/../lib";
use Log::Log4perl qw(get_logger);
use PoolBot::Common;


sub notifyMatter {
  my $text = shift;
  my $config = getConfig('MatterMost');
  my $log = get_logger("Fido::MatterMost");

  unless ($config->{'webHookURL'}) {
    return;
  }

  my $attach = ();
  $attach->{'text'} = $text;

  if ($config->{'iconUrl'}) {
    $attach->{'icon_url'} = $config->{'iconUrl'};
  }

  $attach->{'username'} = $config->{'botName'};
  if ($config->{'channel'}) {
    $attach->{'`channel'} = $config->{'channel'};
  }

  # encode the json
  my $jsonBody = encode_json $attach;

  my $response = postURL($config->{'webHookURL'},$jsonBody);
  return $response;
}
