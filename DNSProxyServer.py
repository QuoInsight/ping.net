# https://github.com/tigerlyb/DNS-Proxy-Server-in-Python
# [ ported to Python 3.4 and enhanced by QuoInsight ]
#
# For Testing:
#  Run the server at port 6760 as the follow command:
#   python DNSserver.py 8.8.8.8 6760
#  Test the server:
#   dig -p 6760 @127.0.0.1 google.com
#   dig -p 6760 @127.0.0.1 +tcp google.com
#   nslookup - 127.0.0.1
#    set port=6760
#    google.com
# 
# If an UDP DNS request is coming, the server will start a new thread
# to handler this request, convert the UDP request to TCP and send it
# to the upstream DNS server. If the request is not a DNS query, the
# server will drop it. When the server got the TCP answer from upstream
# DNS server, it will convert to UDP answer and send it back to the client.
# 
# Description: This project is to design and develop a DNS proxy.
# A DNS proxy is a DNS forwarder program that acts as a DNS resolver
# for client programs but requires an upstream DNS server to perform
# the DNS lookup. The DNS proxy receives queries from outside and
# forward queries to a DNS server.
# 
# For this project, the proxy is required to receive queries in UDP mode,
# which is the default transport protocol for DNS. However, for forwarding
# query to a DNS server, TCP should be used by the proxy. No caching
# capacity is required.
# 
# The proxy should only forward valid DNS request. For incoming UDP packets
# that do not have a valid DNS header, those packets should be discarded.
# 
# This proxy program take two command line arguments:
#  1. upstream DNS server IP address;
#  2. local UDP port number for the proxy.
#

import socket
import sys
import struct
import _thread ## The thread module has been "deprecated" for quite a long time.
               ## Users are encouraged to use the threading module instead.
               ## Hence, in Python 3, the module "thread" is not available anymore.
               ## However, it has been renamed to "_thread" for backwards compatibilities in Python3.
import codecs

# send a TCP DNS query to the upstream DNS server
def sendUpstrmQuery(server, port, sockTyp, qryMsg):
  sock = socket.socket(socket.AF_INET, sockTyp)
  print("sendUpstrmQuery "+server+":"+str(port)+" ... "+str(sock.type))
  sock.connect((server, port))
  sock.send(qryMsg)
  data = sock.recv(1024)
  print("**upstrmResponse: " + str(data))
  return data
#

def addMsgSzPrefix(msg) :
  # ==convert the UDP DNS message to the TCP DNS message==
  # The TCP message is prefixed with a two byte length field which gives
  # the message length, excluding the two byte length field. This length
  # field allows the low-level processing to assemble a complete message
  # before beginning to parse it. [RFC 1035]
  return b''.join([len(msg).to_bytes(2,byteorder='big'), msg])
#

# a new thread to handle the UPD DNS request to TCP DNS request
def handler(data, addr, c, sock, upstrmServer, upstrmPort, upstrmSockTyp):
  #print("Request from client: ", data.decode("hex"), addr)
  print("**localQuery: " + str(data))
  # DNS Message Header Format (total 4+8bytes)
  # ID:2bytes; Flags+OpCode+RespCode:2bytes; RecordsCount:4*2bytes
  # http://www.tcpipguide.com/free/t_DNSMessageHeaderandQuestionSectionFormat.htm
  if ( upstrmSockTyp == sock.type ) :
    upstrmQuery = data
  elif ( sock.type == socket.SOCK_STREAM ) :
    # ==convert the TCP DNS Request to the UDP by skipping the first 2 bytes==
    upstrmQuery = data[2:]
  else :
    # ==convert the UDP DNS query to the TCP DNS query==
    upstrmQuery = addMsgSzPrefix(data)
    print("**upstrmQuery["+str(len(upstrmQuery)-2)+"+2]: " + str(upstrmQuery))
  #
  upstrmAnswer = sendUpstrmQuery(upstrmServer, upstrmPort, upstrmSockTyp, upstrmQuery)
  #print("Answer from server: ", upstrmAnswer.decode("hex"))
  if upstrmAnswer and len(upstrmAnswer) >= 12 :
    if ( upstrmSockTyp == socket.SOCK_STREAM ) :
      tcpAnswer = upstrmAnswer
      udpAnswer = upstrmAnswer[2:]
    else :
      udpAnswer = upstrmAnswer
      tcpAnswer = addMsgSzPrefix(upstrmAnswer)
    #
    try :
      msgHeader = codecs.encode(udpAnswer[:12], "hex").decode() # total:4+8bytes
      print("msgHeader: ", msgHeader) ## [ID:0123][Flag&Codes:4567][RecordCounts:8901,2345,6789,0123]
      rcode = int(msgHeader[7], 16)
      print("rcode: ", rcode)
      if (rcode == 1) :
        print("Request is not a DNS query. Format Error!")
      elif (rcode != 0) :
        print("Error Response ["+str(rcode)+"]!")
      else :
        print("Success!")
      #
    except Exception as e:
      print(e)
    #
    if ( sock.type == socket.SOCK_DGRAM ) :
      sock.sendto(udpAnswer, addr)
    else :
      c.sendall(tcpAnswer)
    #
  else:
    print("Invalid Response!")
  #
#

if __name__ == '__main__':
  upstrmServer = "8.8.8.8" ## "192.168.43.1" ## "8.8.8.8" ## sys.argv[1] ## !! 192.168.192.1 ==> tcpNotSupported ## 
  upstrmPort = 53
  upstrmSockTyp = socket.SOCK_STREAM ## udp: socket.SOCK_DGRAM | tcp:socket.SOCK_STREAM
  localhost = '' ## '127.0.0.1'
  localport = 6760 ## 53 ## int(sys.argv[2])
  localSockTyp = socket.SOCK_DGRAM ## udp: socket.SOCK_DGRAM | tcp:socket.SOCK_STREAM
  if len(sys.argv) > 2 :
    upstrmServer = sys.argv[1]
    localport = int(sys.argv[2])
  #
  try:
    sock = socket.socket(socket.AF_INET, localSockTyp)
    print("starting "+localhost+":"+str(localport)+" ... "+str(sock.type))
    sock.bind((localhost, localport))  ## netstat -ano | findstr 53
    if (sock.type==socket.SOCK_STREAM): sock.listen(1);
    while True:
      if (sock.type==socket.SOCK_STREAM):
        c, addr = sock.accept();  data = c.recv(1024)
      else :
        c = None;  data, addr = sock.recvfrom(1024)
      #
      print("\nNewQuery from "+str(addr)+" ...")
      _thread.start_new_thread(handler, (data, addr, c, sock, upstrmServer, upstrmPort, upstrmSockTyp))
    #
  except Exception as e:
    print(e)
    sock.close()
  #
#
