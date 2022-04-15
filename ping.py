#!/usr/bin/env python

"""
   A pure python ping implementation using raw socket.

   Note that ICMP messages can only be sent from processes running as root.

   Derived from ping.c distributed in Linux's netkit. That code is
   copyright (c) 1989 by The Regents of the University of California.
   That code is in turn derived from code written by Mike Muuss of the
   US Army Ballistic Research Laboratory in December, 1983 and
   placed in the public domain. They have my thanks.

   Bugs are naturally mine. I'd be glad to hear about them. There are
   certainly word - size dependenceies here.

   Copyright (c) Matthew Dixon Cowles, <http://www.visi.com/~mdc/>.
   Distributable under the terms of the GNU General Public License
   version 2. Provided with no warranties of any sort.

   Original Version from Matthew Dixon Cowles:
     -> ftp://ftp.visi.com/users/mdc/ping.py

   Rewrite by Jens Diemer:
     -> http://www.python-forum.de/post-69122.html#69122

   Rewrite by Johannes Meyer:
     -> http://www.python-forum.de/viewtopic.php?p=183720

   Ported to Python 3 by KL Lai:
     -> based on the version at https://gist.github.com/pklaus/856268

   Revision history
   ~~~~~~~~~~~~~~~~

   November 1, 2010
   Rewrite by Johannes Meyer:
    -  changed entire code layout
    -  changed some comments and docstrings
    -  replaced time.clock() with time.time() in order
       to be able to use this module on linux, too.
    -  added global __all__, ICMP_CODE and ERROR_DESCR
    -  merged functions "do_one" and "send_one_ping"
    -  placed icmp packet creation in its own function
    -  removed timestamp from the icmp packet
    -  added function "multi_ping_query"
    -  added class "PingQuery"

   May 30, 2007
   little rewrite by Jens Diemer:
    -  change socket asterisk import to a normal import
    -  replace time.time() with time.clock()
    -  delete "return None" (or change to "return" only)
    -  in checksum() rename "str" to "source_string"

   November 22, 1997
   Initial hack. Doesn't do much, but rather than try to guess
   what features I (or others) will want in the future, I've only
   put in what I need now.

   December 16, 1997
   For some reason, the checksum bytes are in the wrong order when
   this is run under Solaris 2.X for SPARC but it works right under
   Linux x86. Since I don't know just what's wrong, I'll swap the
   bytes always and then do an htons().

   December 4, 2000
   Changed the struct.pack() calls to pack the checksum and ID as
   unsigned. My thanks to Jerome Poincheval for the fix.


   Last commit info:
   ~~~~~~~~~~~~~~~~~
   $LastChangedDate: $
   $Rev: $
   $Author: $
"""

import signal, inspect, sys, time, datetime
import socket, struct, select, random, asyncore

# From /usr/include/linux/icmp.h; your milage may vary.
ICMP_ECHO_REQUEST = 8 # Seems to be the same on Solaris.
ICMP_CODE = socket.getprotobyname('icmp')
ERROR_DESCR = {
    1: ' - Note that ICMP messages can only be '
       'sent from processes running as root.',
    10013: ' - Note that ICMP messages can only be sent by'
           ' users or processes with administrator rights.'
    }

__all__ = ['create_packet', 'do_one', 'verbose_ping', 'PingQuery',
           'multi_ping_query']

SIGTERM_ON = False
nicInfo=""; startTime=datetime.datetime.now(); logFile="ping.net.log";
pingTarget=""; pingCount=0; responseCount=0;
totalResponseTime=0; minResponseTime=-1; maxResponseTime=0;

########################################################################

import subprocess
def exeCmdln(cmd, args, stdin) :
  cmdlineArr=[cmd];  cmdlineArr.extend(args)
  p = subprocess.Popen(
    cmdlineArr, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
  )
  return "\n".join(outData.decode() for outData in p.communicate(input=stdin.encode('ascii')))
#

def getConnectedSsidNetsh(macAddr) :
  ssid = ""
  cmdOutput = ""
  try :
    macAddr = macAddr.replace(":","").replace("-","").upper()
    cmdOutput = exeCmdln("netsh.exe", ["wlan", "show", "interfaces"], "")
    foundMacAddr = False
    for line in cmdOutput.split("\n") :
      if (foundMacAddr) :
        line = line.strip()
        idx = (line.index(":")+1) if (":" in line) else 0
        if "BSSID" in line :
          ssid += " BSSID:" + line[idx:].strip().replace(":","")
        elif "SSID" in line :
          ssid += " " + line[idx:].strip()
        elif "Signal" in line :
          ssid += " [" + line[idx:].strip() + "]"
          break
        #
      else :
        foundMacAddr = ( macAddr in line.upper().replace(":","").replace("-","") )
      #
    #
  except :
    pass
  #
  return ssid
#

#print( getConnectedSsidNetsh("") ); quit()

def getIfName(nicGUID):
  ifName = nicGUID
  if (sys.platform=="win32"):
    import winreg 
    try:
      regKey = winreg.OpenKey(
        winreg.ConnectRegistry(None, winreg.HKEY_LOCAL_MACHINE),
        "SYSTEM\\CurrentControlSet\\Control\\Network\\{4d36e972-e325-11ce-bfc1-08002be10318}\\" + nicGUID + "\\Connection"
      )
      ifName = winreg.QueryValueEx(regKey, 'Name')[0]
      ifName = "[" + ifName + "]"
      #ifType = winreg.QueryValueEx(regKey, 'MediaSubType')[0] ## !! MediaSubType==2 for both lan & wlan !!
      # netsh.exe wlan show interfaces
      # netsh.exe interface show interface
      # netsh.exe interface ip show interfaces
      # wmic.exe nic list full
    except :
      pass
    #
  #
  return ifName
#

def getPublicIP() :
  pubAddr = ""
  try :
    import urllib.request
    pubAddr = urllib.request.urlopen(
      "http://checkip.amazonaws.com/"
    ).read().decode("utf8").strip()
  except :
    pass
  #
  return pubAddr
#

import netifaces ## pip install netifaces
def getNicInfo() :
  hostName = socket.gethostname()
  defaultGW = netifaces.gateways().get("default")
  (gwAddr,gwIf) = defaultGW[netifaces.AF_INET]
  addrs = netifaces.ifaddresses(gwIf) ## {793B7B92-2A7D-4399-B444-450C0846479F}
  macAddr = addrs[netifaces.AF_LINK][0]['addr']
  sckAddr = socket.gethostbyname(hostName)
  ipAddr = ""
  try :
    ipAddr = addrs[netifaces.AF_INET][0]['addr']
  except Exception as e:
    ipAddr = sckAddr
    # print("Error: " + str(e))
  #
  if (ipAddr!=sckAddr) : ipAddr += "/" + sckAddr
  return (
    hostName + " " + getIfName(gwIf) + " MAC:" + macAddr.replace(":","").upper()
     + getConnectedSsidNetsh(macAddr) + "\n IP:" + ipAddr + " GW:" + gwAddr
     + " PUB:" + getPublicIP()
  )
  ## CKL036-05 [Wi-Fi] Type:Wireless80211 MAC:34E12D960AE6
  ##  C1CF@5GHz BSSID:d46e0eeee67e [50%] IP:192.168.0.106 GW:192.168.0.2
  ## CKL036-05 [Wi-Fi] MAC:34E12D960AE6 C1CF@5GHz BSSID:d46e0eeee67e [66%]
  ##  IP:192.168.0.106/10.46.68.207 GW:192.168.0.2
#

# print( getNicInfo() ); quit()

########################################################################

def printSummary() :
  global nicInfo, startTime
  global pingTarget, pingCount, responseCount
  global totalResponseTime, minResponseTime, maxResponseTime

  print("")
  if (nicInfo!=""): print(nicInfo)
  loss = 0 if (pingCount==0) else int(round(100.0*(pingCount-responseCount)/pingCount,0))
  avg = 0 if (responseCount==0) else int(round(totalResponseTime/responseCount,0))
  print(
    "Target:" + pingTarget + " Duration:" + startTime.strftime('%Y-%m-%d %H:%M:%S')
    + " - " + datetime.datetime.now().strftime('%H:%M:%S') + "\n"
    + "Reply:" + str(responseCount) + "/" + str(pingCount) + " (" + str(loss) + "% loss) "
    + "Min:" + str(int(round(minResponseTime))) + "ms Max:" + str(int(round(maxResponseTime))) + "ms Avg:" + str(avg) + "ms"
  )
  return
#

def signalHandler(signum, frame):
#  try:
#    signalName = signal.Signals(signum).name
#  except:
#    signalsDict = dict(
#      (k, v) for v, k in reversed(sorted(signal.__dict__.items())) if v.startswith('SIG') and not v.startswith('SIG_')
#      ## (getattr(signal, n), n) for n in dir(signal) if n.startswith('SIG') and '_' not in n 
#    )
#    signalName = signalsDict[signum]
#  #
#
#  frameInfo = ""
#  if (frame.f_back is not None): frameInfo = str(inspect.getframeinfo(frame.f_back))
#  ## frameInfo = str(traceback.print_stack(frame))
#
#  print("signalHandler: " + signalName + " [" + str(signum) + "] " + frameInfo)
#
#  print("f_back: " + str(frame.f_back))
#  print("f_code: " + str(frame.f_code))
#  print("f_lasti: " + str(frame.f_lasti))
#  print("f_lineno: " + str(frame.f_lineno))
#  ## print("f_builtins: " + str(frame.f_builtins)) ## this is too detailed
#  ## print("f_globals: " + str(frame.f_globals))
#  ## print("f_locals: " + str(frame.f_locals))
#  print("f_trace: " + str(frame.f_trace))

  if (signum==signal.SIGTERM or signum==signal.SIGINT) :
    SIGTERM_ON = True
    print("terminating ...") 
    #print("terminating ... wait for last ping reply before printing summary ...")
  #elif (signum==signal.SIGALRM) :  ## not supported on Windows
    nicInfo = getNicInfo()
    printSummary()
    time.sleep(30) ## delay before exit
    sys.exit()
  #
#
signal.signal(signal.SIGTERM, signalHandler) # kill
signal.signal(signal.SIGINT, signalHandler) # ctrl-c
## signal.signal(signal.SIGALRM, signalHandler) # not supported on Windows

########################################################################

def checksum(source_string):
    # I'm not too confident that this is right but testing seems to
    # suggest that it gives the same answers as in_cksum in ping.c.
    sum = 0
    count_to = (len(source_string) / 2) * 2
    count = 0
    while count < count_to:
        this_val = (source_string[count + 1])*256 + (source_string[count])
        sum = sum + this_val
        sum = sum & 0xffffffff # Necessary?
        count = count + 2
    if count_to < len(source_string):
        sum = sum + ord(source_string[len(source_string) - 1])
        sum = sum & 0xffffffff # Necessary?
    sum = (sum >> 16) + (sum & 0xffff)
    sum = sum + (sum >> 16)
    answer = ~sum
    answer = answer & 0xffff
    # Swap bytes. Bugger me if I know why.
    answer = answer >> 8 | (answer << 8 & 0xff00)
    return answer


def create_packet(id, dataSz=56):
    """Create a new echo request packet based on the given "id"."""
    # Header is type (8), code (8), checksum (16), id (16), sequence (16)
    header = struct.pack('bbHHh', ICMP_ECHO_REQUEST, 0, 0, id, 1)
    data = bytes(dataSz*'Q', 'ascii') ## 
    # Calculate the checksum on the data and the dummy header.
    my_checksum = checksum(header + data)
    # Now that we have the right checksum, we put that in. It's just easier
    # to make up a new header than to stuff it into the dummy.
    header = struct.pack('bbHHh', ICMP_ECHO_REQUEST, 0,
                         socket.htons(my_checksum), id, 1)
    return header + data


def do_one(dst_addr, timeout=1):
    """
   Sends one ping to the given "dst_addr" which can be an ip or hostname.
   "timeout" can be any integer or float except negatives and zero.

   Returns either the delay (in seconds) or None on timeout and an invalid
   address, respectively.

   """
    try:
        my_socket = socket.socket(socket.AF_INET, socket.SOCK_RAW, ICMP_CODE)
    except socket.error as err:
        if err.errno in ERROR_DESCR:
            # Operation not permitted
            raise socket.error(''.join((msg, ERROR_DESCR[err.errno])))
        raise # raise the original error
    try:
        host = socket.gethostbyname(dst_addr)
    except socket.gaierror:
        return
    # Maximum for an unsigned short int c object counts to 65535 so
    # we have to sure that our packet id is not greater than that.
    packet_id = int((id(timeout) * random.random()) / 65535)
    packet = create_packet(packet_id, 32)
    #print("snd_packet[" + str(len(packet)) + "]: " + str(packet))
    while packet:
        # The icmp protocol does not use a port, but the function
        # below expects it, so we just give it a dummy port.
        sent = my_socket.sendto(packet, (dst_addr, 1))
        packet = packet[sent:]
    #
    (delay, addr, ipHeaders) = receive_ping(my_socket, packet_id, time.time(), timeout)
    my_socket.close()
    return (delay, addr, ipHeaders)
# do_one


#import ipaddress
def ipBytes2Addr(val):
  #return str(ipaddress.ip_address(val))
  ## https://docs.python.org/3/library/struct.html#format-characters
  (b4,b3,b2,b1) = struct.unpack("BBBB", struct.pack("L", val))
  return "{:d}.{:d}.{:d}.{:d}".format(b1,b2,b3,b4)
#


def header2dict(names, struct_format, data):
    ## https://stackoverflow.com/a/37652198/2940478
    ## https://docs.python.org/3/library/struct.html#format-characters
    """ unpack the raw received IP and ICMP header informations to a dict """
    unpacked_data = struct.unpack(struct_format, data)
    return dict(zip(names, unpacked_data))


def receive_ping(my_socket, packet_id, time_sent, timeout):
    # Receive the ping from the socket.
    time_left = timeout
    rcv_packet_sz = 0
    while True:
        started_select = time.time()
        ready = select.select([my_socket], [], [], time_left)
        how_long_in_select = time.time() - started_select
        if ready[0] == []: return # Timeout

        time_received = time.time()
        delay = (time_received - time_sent)

        rcv_packet, addr = my_socket.recvfrom(1024)
        rcv_packet_sz += (len(rcv_packet)-20-8) ## minus 20 bytes IP header and 8 bytes for the ICMP header
        #print("addr: " + str(addr))
        #print("rcv_packet[" + str(len(rcv_packet)) + "]: " + str(rcv_packet))

        ipHeaders = header2dict(
            names=["version", "type", "length",
             "id", "flags", "ttl", "protocol",
             "checksum", "src_ip", "dst_ip"
            ],
            struct_format="!BBHHHBBHII",
            data=rcv_packet[:20]
        )
        ##print("src_ip [" + str(ipHeaders["src_ip"]) + "]: " + ipBytes2Addr(ipHeaders["src_ip"]))
        ##print("dst_ip [" + str(ipHeaders["dst_ip"]) + "]: " + ipBytes2Addr(ipHeaders["dst_ip"]))

        icmpHeaders = header2dict(
          names=["type", "code", "checksum", "p_id"],
          struct_format="bbHHh", data=rcv_packet[20:28]
        )
        if icmpHeaders["p_id"] == packet_id:
           ipHeaders["packet_size"] = rcv_packet_sz
           return (delay, addr, ipHeaders)
        #
        time_left -= delay
        if time_left <= 0: return
    # while True
# receive_ping

import datetime
def verbose_ping(dst_addr, timeout=2, count=4):
    """
   Sends one ping to the given "dst_addr" which can be an ip or hostname.

   "timeout" can be any integer or float except negatives and zero.
   "count" specifies how many pings will be sent.

   Displays the result on the screen.

   """
    global pingTarget, pingCount, responseCount
    global totalResponseTime, minResponseTime, maxResponseTime 
    pingTarget = dst_addr

    last20Queue = [];  lastResponseTime = -1;  lastFailRate = 0;
    currentFailRate = 0;

    print('ping {}...'.format(dst_addr))
    i = 0
    while (count==-1 or i<count) :
        i += 1
        pingCount += 1
        try :
            responseTime, addr, ipHeaders = do_one(dst_addr, timeout)
        except Exception as err :
            responseTime = None
            print("ERROR: " + str(err))
        #
        if responseTime == None:
            last20Queue.append(0);
            print('failed. (Timeout within {} seconds.)'.format(timeout))
        else:
            responseCount += 1
            last20Queue.append(1);
            responseTime = round(responseTime*1000.0)

            statusCode = ": "
            totalResponseTime += responseTime
            if (minResponseTime < 0 or responseTime < minResponseTime): minResponseTime = responseTime
            if (responseTime > maxResponseTime):
              maxResponseTime = responseTime
              statusCode = "^^"
            elif (responseCount > 0 and responseTime > round(totalResponseTime/responseCount)) :
              statusCode = "^ ";
            #
            print(
              '{:02.0f}{}{} Reply from {}: bytes={:d} time={:.0f}ms TTL={:d}'.format(
                 currentFailRate, statusCode,
                 datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3],
                 ipBytes2Addr(ipHeaders["src_ip"]), ## str(addr)
                 ipHeaders["packet_size"], responseTime, ipHeaders["ttl"]
              )
            )
        #
        if ( len(last20Queue) > 20): last20Queue.pop(0);
        last20Pass=0
        for item in last20Queue: last20Pass+=item
        currentFailRate = 100*(len(last20Queue)-last20Pass)/len(last20Queue)

        lastResponseTime = responseTime
        lastFailRate = currentFailRate

        if (SIGTERM_ON) :
          # SIGALRM not supported on Windows
          signal.alarm(0) ## timeout=0; OK for program to printSummary() and exit!
          break
        #
        time.sleep(1)
    #
    print


class PingQuery(asyncore.dispatcher):
    def __init__(self, host, p_id, timeout=0.5, ignore_errors=False):
        """
       Derived class from "asyncore.dispatcher" for sending and
       receiving an icmp echo request/reply.

       Usually this class is used in conjunction with the "loop"
       function of asyncore.

       Once the loop is over, you can retrieve the results with
       the "get_result" method. Assignment is possible through
       the "get_host" method.

       "host" represents the address under which the server can be reached.
       "timeout" is the interval which the host gets granted for its reply.
       "p_id" must be any unique integer or float except negatives and zeros.

       If "ignore_errors" is True, the default behaviour of asyncore
       will be overwritten with a function which does just nothing.

       """
        asyncore.dispatcher.__init__(self)
        try:
            self.create_socket(socket.AF_INET, socket.SOCK_RAW, ICMP_CODE)
        except socket.error as err:
            if err.errno in ERROR_DESCR:
                # Operation not permitted
                raise socket.error(''.join((msg, ERROR_DESCR[err.errno])))
            raise # raise the original error
        self.time_received = 0
        self.time_sent = 0
        self.timeout = timeout
        # Maximum for an unsigned short int c object counts to 65535 so
        # we have to sure that our packet id is not greater than that.
        self.packet_id = int((id(timeout) / p_id) / 65535)
        self.host = host
        self.packet = create_packet(self.packet_id, 32)
        if ignore_errors:
            # If it does not care whether an error occured or not.
            self.handle_error = self.do_not_handle_errors
            self.handle_expt = self.do_not_handle_errors

    def writable(self):
        return self.time_sent == 0

    def handle_write(self):
        self.time_sent = time.time()
        while self.packet:
            # The icmp protocol does not use a port, but the function
            # below expects it, so we just give it a dummy port.
            sent = self.sendto(self.packet, (self.host, 1))
            self.packet = self.packet[sent:]

    def readable(self):
        # As long as we did not sent anything, the channel has to be left open.
        if (not self.writable()
            # Once we sent something, we should periodically check if the reply
            # timed out.
            and self.timeout < (time.time() - self.time_sent)):
            self.close()
            return False
        # If the channel should not be closed, we do not want to read something
        # until we did not sent anything.
        return not self.writable()

    def handle_read(self):
        read_time = time.time()
        packet, addr = self.recvfrom(1024)
        header = packet[20:28]
        type, code, checksum, p_id, sequence = struct.unpack("bbHHh", header)
        if p_id == self.packet_id:
            # This comparison is necessary because winsocks do not only get
            # the replies for their own sent packets.
            self.time_received = read_time
            self.close()

    def get_result(self):
        """Return the ping delay if possible, otherwise None."""
        if self.time_received > 0:
            return self.time_received - self.time_sent

    def get_host(self):
        """Return the host where to the request has or should been sent."""
        return self.host

    def do_not_handle_errors(self):
        # Just a dummy handler to stop traceback printing, if desired.
        pass

    def create_socket(self, family, type, proto):
        # Overwritten, because the original does not support the "proto" arg.
        sock = socket.socket(family, type, proto)
        sock.setblocking(0)
        self.set_socket(sock)
        # Part of the original but is not used. (at least at python 2.7)
        # Copied for possible compatiblity reasons.
        self.family_and_type = family, type

    # If the following methods would not be there, we would see some very
    # "useful" warnings from asyncore, maybe. But we do not want to, or do we?
    def handle_connect(self):
        pass

    def handle_accept(self):
        pass

    def handle_close(self):
        self.close()


def multi_ping_query(hosts, timeout=1, step=512, ignore_errors=False):
    """
   Sends multiple icmp echo requests at once.

   "hosts" is a list of ips or hostnames which should be pinged.
   "timeout" must be given and a integer or float greater than zero.
   "step" is the amount of sockets which should be watched at once.

   See the docstring of "PingQuery" for the meaning of "ignore_erros".

   """
    results, host_list, id = {}, [], 0
    for host in hosts:
        try:
            host_list.append(socket.gethostbyname(host))
        except socket.gaierror:
            results[host] = None
    while host_list:
        sock_list = []
        for ip in host_list[:step]: # select supports only a max of 512
            id += 1
            sock_list.append(PingQuery(ip, id, timeout, ignore_errors))
            host_list.remove(ip)
        # Remember to use a timeout here. The risk to get an infinite loop
        # is high, because noone can guarantee that each host will reply!
        asyncore.loop(timeout)
        for sock in sock_list:
            results[sock.get_host()] = sock.get_result()
    return results

def main(argv) :
    _thisScript_ = argv[0]  ## __file__

    global nicInfo, pingTarget, logFile
    nicInfo = getNicInfo()
    print(nicInfo + "\n")

    pingTarget = ( argv[1] if (len(argv)>1) else "www.google.com" )
    count = ( argv[2] if (len(argv)>2) else "" )
    count = int(count) if count.lstrip('+-').isnumeric() else 1800
    if (len(argv)>3): logFile = argv[3]
    if (logFile=="-"): logFile=""

    if (pingTarget=="/?" or pingTarget=="-?" or pingTarget=="?" or pingTarget=="/h" or pingTarget=="-h" or pingTarget=="/help" or pingTarget=="-help") :
      print()
      print("Syntax: ping.py [ipAddr/hostName [count [logFile]]]")
      print("Default: ping.py <defaultGateway> 1800 ping.net.log")
      print()
      return
    #

    verbose_ping(pingTarget, count=count)
    return
#


if __name__ == '__main__':
    main(sys.argv)

    # Testing
    #verbose_ping('www.heise.de')
    #verbose_ping('www.google.com', count=-1)
    #verbose_ping('an-invalid-test-url.com')
    #verbose_ping('127.0.0.1')
    #host_list = ['www.heise.de', 'google.com', '127.0.0.1', 'an-invalid-test-url.com']
    #for host, ping in multi_ping_query(host_list).iteritems():
    #    print(host, '=', ping)
#
