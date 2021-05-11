#!/usr/bin/perl

  if ($ARGV[0] eq "" || join('', @ARGV) =~ /\?/ ) {
    print "\nUsage: netcat.pl host[:port] [file]\n\n";
    exit;
  }

  ($host,$port) = split(/:/, $ARGV[0]);  $port=9100 unless $port;
  $file=$ARGV[1]; $file="&STDIN" unless $file;

  #http://aplawrence.com/SCOFAQ/FAQ_scotec7getnetcat.html

  use IO::Socket;
  $socket=IO::Socket::INET->new(PeerAddr=>$host, PeerPort=>$port, 
             Proto=>'tcp',Type=>SOCK_STREAM) or die "Can't talk to [$host:$port]";
    open(F,"<$file"); while(<F>) {
      print $socket $_;
    } close(F);
  close $socket;
