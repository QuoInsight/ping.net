#!/usr/bin/perl

use IO::Socket::INET;

sub sendData {
  my ($targetHost, $targetPort, $reqString) = @_;
  my $respString = "";
  #return $respString;
  my $socket = new IO::Socket::INET (
    PeerHost => $targetHost, PeerPort => $targetPort, Proto => 'tcp',
  ); return "cannot connect to the server $!n" unless $socket;

  # data to send to a server
  my $size = $socket->send($reqString);  #print "sent data of length $sizen";
  shutdown($socket, 1);  # notify server that request has been sent
  # receive a response of up to 4096 characters from server
  $socket->recv($respString, 4096);
  $socket->close();
  return $respString;
}

print sendData("www.google.com", "80", "GET /");
