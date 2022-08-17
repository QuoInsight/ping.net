#!/usr/bin/env lua

import sys
import socket

dnsServer = "8.8.8.8"
dnsPort = 53
qType = 1
hostName = "google.com"

if len(sys.argv) < 2 :
  print("\nUsage: "+sys.argv[0]+" <HOST> [QRY_TYPE [DNS_SERVER [DNS_PORT]]]\n")
  quit()
#
if len(sys.argv)>4 : dnsPort=sys.argv[4] #
if len(sys.argv)>3 : dnsServer=sys.argv[3] #
if len(sys.argv)>2 : qType=sys.argv[2] #
if len(sys.argv)>1 : hostName=sys.argv[1]

if qType=="A" : qType=1 #
if qType=="AAAA" : qType=28 #
qType = int(qType)

##print(hostName+"["+qType+"]"+"@"+dnsServer+":"+dnsPort)

########################################################################

def bytes2Num(bytes) :
  #byteorder is "big" ==> most significant byte is at the beginning ==> little endian
  return int.from_bytes(bytes, byteorder='big', signed=False)
#
def byte2Bits(n) :
  return bin(n).lstrip('0b')
#
def bytes2Hex(bytes) :
  return ''.join('{:02x}'.format(x) for x in bytes)
#

def hex2Str(s) :
  return bytearray.fromhex(s).decode() # s.decode("hex")
#
def str2Hex(s) :
  return bytes2Hex(s.encode("latin-1"))
#

########################################################################

def ipAddrBytes2Str(bytes) :
  aAddr = ""
  if (len(bytes)==4) :
    aAddr = ( str(bytes[0]) + "." + str(bytes[1])
      + "." + str(bytes[2])  + "." + str(bytes[3])
    )
  elif (len(s)==16) :
    aAddr = ( bytes2Hex(bytes[0:1])
      + ":" + bytes2Hex(bytes[2:3])
      + ":" + bytes2Hex(bytes[4:5])
      + ":" + bytes2Hex(bytes[6:7])
      + ":" + bytes2Hex(bytes[8:9])
      + ":" + bytes2Hex(bytes[10:11])
      + ":" + bytes2Hex(bytes[12:13])
      + ":" + bytes2Hex(bytes[14:15])
    )
  else :
    aAddr = bytes2Hex(s)
  #
  return aAddr
#

########################################################################

def findEndOfNameData(rawData, startIdx) :
  idx = startIdx
  while True :
    sz1 = rawData[idx]
    if sz1==0 :
      return idx
    elif sz1<64 :
      idx = idx+sz1+1
      if idx > len(rawData) :
        return nil ## data error
      #
    else : ## elif sz1>=192 :
      return idx+1
      ## 4.1.4. Message compression https://datatracker.ietf.org/doc/html/rfc1035
      ## if a reference/pointer is found/used, it must either be the only element
      ## or the last element !! no additional null character after this !!
      ## hence, we should return immediately and ends here
    #
  #
  return nil
#

########################################################################

def qryDns(qName, qType, srv, prt, sck) :
  def getRnd2Chrs() :
    ## max value of 2 bytes == 65535 ##
    import time;  t = time.time()
    import random;  random.seed()
    return chr(round((t%10)/10*255)) + chr(random.randrange(255))
  #
  def encodeNameData(qName) :
    qData = ""
    for n1 in qName.split('.') :
      qData = qData + chr(len(n1)) + n1
    #
    ##print(str2Hex(qData))
    return qData
  #
  def parseAnswer(msgData, qType) :
    ##msgHdrHex = str2Hex(msgData:sub(1,12)) ; print(msgHdrHex)
    ## ID:2bytes; Flags+OpCode+RespCode:2bytes; RecordsCount:4*2bytes
    byte4 = byte2Bits(msgData[3])
    rspCode = int(byte4[4:], 2)
    qCount = bytes2Num(msgData[4:6])
    aCount = bytes2Num(msgData[6:8])
    ##print("aCount: "+str(aCount))
    byteIdx = 12
    for count in range(qCount) :
      endOfNameData = findEndOfNameData(msgData, byteIdx)
      byteIdx = endOfNameData+1+4 ## end of q1
    #
    if (qCount>=1 and aCount > 0) :
      for count in range(aCount) :
        endOfNameData = findEndOfNameData(msgData, byteIdx)
        byteIdx = endOfNameData+1 ## end of a1
        aType = bytes2Num(msgData[byteIdx:byteIdx+2]) ## 1:A(ipv4)|28:AAAA(ipv6)| https://en.wikipedia.org/wiki/List_of_DNS_record_types#Resource_records
        aClass = bytes2Num(msgData[byteIdx+2:byteIdx+4]) ## normally the value 1 for Internet ('IN')
        ##print("aType:"+str(aType)+" qType:"+str(qType))
        byteIdx = byteIdx+8 ##
        aSize = bytes2Num(msgData[byteIdx:byteIdx+2])
        byteIdx = byteIdx+2 ##
        if (aType==qType) :
          aData = msgData[byteIdx:byteIdx+aSize]
          if (aType==1 or aType==28) :
            return ipAddrBytes2Str(aData)
          else :
            return bytes2Hex(aData)
          #
        #
        byteIdx = byteIdx+aSize
      #
    #
    if (qType==1) :
      return "0.0.0.0"
    elif (qType==28) :
      return "::"
    else :
      return "#"
    #
  #

  qryData = ( getRnd2Chrs() + hex2Str("01000001000000000000") \
    + encodeNameData(qName) + hex2Str("0000") \
    + chr(qType) + hex2Str("0001")
  ).encode("latin-1")
  #print(bytes2Hex(qryData)); print(qryData);

  ##sck.bind(('', 40053)) ## use specific source port !!
  ##sck.connect((srv, prt)); sck.send(qryData) ## this is more standard/proper ??
  sck.sendto(qryData, (srv, prt)) ## this will be more compatible/flexible !!
  #print("sent")

  rspData = sck.recv(1024)
  #print("received")
  if rspData :
    #print(bytes2Hex(rspData)); ##print(rspData)
    return parseAnswer(rspData, qType)
  else :
    print("Error")
  #
#

print( qryDns(hostName, qType, dnsServer, dnsPort, socket.socket(socket.AF_INET,socket.SOCK_DGRAM)) )
