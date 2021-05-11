use IO::Socket::INET;

sub sendData {
  my ($targetHost, $targetPort, $reqString) = @_;
  my $buf="", $respString="";
  my $socket = new IO::Socket::INET (
    PeerHost => $targetHost, PeerPort => $targetPort,
    Proto => 'tcp', Type=>IO::Socket::SOCK_STREAM
  ); return "cannot connect to the server $!n" unless $socket;

  $socket->autoflush(1);  # http://www.rocketaware.com/perl/perlipc/TCP_Clients_with_IO_Socket.htm
  print $socket $reqString;
  while (defined($buf=<$socket>)) {
    $respString .= $buf;
  }

  # data to send to a server
  # my $size = $socket->send($reqString);  #print "sent data of length $sizen";
  # shutdown($socket, 1);  # notify server that request has been sent
  # $socket->recv($respString, 4096);  # receive a response of up to 4096 characters from seerver

  $socket->close();
  return $respString;
}

#print sendData("www.google.com", "80", "GET / HTTP/1.0 \r\n\r\n");

print sendData(
  "info.cern.ch", "80", "GET / HTTP/1.0\r\n"
  . "Host: info.cern.ch\r\n"
  . "\r\n"
);

