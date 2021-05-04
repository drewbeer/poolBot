package PoolBot::HTTPD;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(startHTTPd);

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Log::Log4perl qw(get_logger);
use AnyEvent::HTTPD;
use JSON;
use PoolBot::Common;
use PoolBot::Relays;
use PoolBot::System;

sub startHTTPd {
  # load config
  my $log = get_logger("PoolBot::HTTPd");
  my $httpConfig = getConfig('httpd');

  my $httpd = AnyEvent::HTTPD->new (
    port => $httpConfig->{'listenPort'},
    host => $httpConfig->{'listenHost'},
    request_timeout => $httpConfig->{'timeout'},
  );

  $httpd->reg_cb (
    '/' => sub {
        $log->debug('/ called');
        my ($httpd, $req) = @_;
        $req->respond ({ content => ['text/html',
           "<html><body>Splish Splash I'm the Pool Bot"
           . "</body></html>"
        ]});
        $httpd->stop_request;
    },
    '/lights/cycle' => sub {
        $log->debug('/lights/cycle called');
        my ($httpd, $req) = @_;
        lightCycle();
        $req->respond ({ content => ['text/html',"cycled"]});
        $httpd->stop_request;
    },
    '/ping' => sub {
        my ($httpd, $req) = @_;
        $log->debug('/ping called');
        $req->respond ({ content => ['text/html',"pong"]});
        $httpd->stop_request;
    },
    '/pool/run' => sub {
        my ($httpd, $req) = @_;
        $log->debug('/pool/run called');
        my $json = $req->content();
        my $data = decode_json $json;
        my $response;
        if ($data->{'program'} && $data->{'duration'} && $data->{'relay'}) {
          $response = runPool($data->{'program'}, $data->{'duration'}, $data->{'relay'});
        } elsif ($data->{'program'} && $data->{'duration'}) {
          $response = runPool($data->{'program'}, $data->{'duration'});
        } else {
          $response = 'missing values for running pool';
        }
        $req->respond ({ content => ['text/html',$response]});
        $httpd->stop_request;
    },
    '/pool/stop' => sub {
        $log->debug('/pool/stop called');
        my ($httpd, $req) = @_;
        my $json = $req->content();
        my $response = stopPool('salt');
        $req->respond ({ content => ['text/html',$response]});
        $httpd->stop_request;
    },
    '/relay/set' => sub {
        my ($httpd, $req) = @_;
        my $json = $req->content();
        my $data = decode_json $json;
        $data->{'value'} = relaySet($data->{'name'}, $data->{'value'});
        my $jsonOut = encode_json $data;
        $req->respond ({ content => ['application/json', $jsonOut]});
        $httpd->stop_request;
    },
    '/status' => sub {
        my ($httpd, $req) = @_;
        $log->debug('/status called');
        my $statusData = getSystemInfo();
        my $statusJson = encode_json $statusData;
        $req->respond ({ content => ['application/json', $statusJson]});
        $httpd->stop_request;
    },
    '/service/pump/start' => sub {
        my ($httpd, $req) = @_;
        my $json = $req->content();
        my $response = servicePumpController('start');
        $req->respond ({ content => ['text/html',$response]});
        $httpd->stop_request;
    },
    '/service/pump/stop' => sub {
        my ($httpd, $req) = @_;
        my $json = $req->content();
        my $response = servicePumpController('stop');
        $req->respond ({ content => ['text/html',$response]});
        $httpd->stop_request;
    },
    '' => sub {
           my ( $httpd, $req ) = @_;
           $req->respond( [ 404, 'not here', {}, '' ] );
           $httpd->stop_request;
    },
  );

  $log->info("starting web server on $httpConfig->{listenHost}:$httpConfig->{'listenPort'}");
  $httpd->run;
}

1;
