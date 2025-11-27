#!/usr/bin/env python3

import time
import datetime
import pexpect

startTime0 = datetime.datetime.now(datetime.timezone.utc)

def exec(cmdln, prompt, ptimeout) :
  startTime = datetime.datetime.now(datetime.timezone.utc)
  print( startTime.strftime("%Y-%m-%d %H:%M:%S GMT+0") )
  print( cmdln )
  try :
    p = pexpect.spawn(cmdln)
  except :
    print("Failed to launch [ "+cmdln+" ]")
    return
  #
  r = -1
  try :
    #p.timeout = ptimeout # default=30s
    r = p.expect(prompt, timeout=ptimeout)
    if r == 0 :
      print("connected successfully")
    #
  except pexpect.exceptions.TIMEOUT:
    print("pexpect.TIMEOUT")
    return
  except pexpect.exceptions.EOF:
    print("pexpect.EOF")
    return
  except Exception as e:
    print(f"An unexpected error occurred: {e}")
    return
  finally:
    if 'p' in locals() :
      print( (p.before).decode() + (prompt if r==0 else "") )
      if p.isalive() : p.close(force=False)
      print(f"exit status: {p.exitstatus}")
      print(f"signal status: {p.signalstatus}")
    #
  #
  endTime = datetime.datetime.now(datetime.timezone.utc)
  print( "Total duration: " + str(round((endTime-startTime).total_seconds(),2)) + " seconds" )
  return r
#

sftp_o = "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
# -oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa
# -oPreferredAuthentications=password -oPubkeyAuthentication=no
cmdln = "sftp " + sftp_o + " -P 2222 demo@demo.wftpserver.com"
cmdln = "sftp " + sftp_o + " demo@test.rebex.net"

count = 0 ; count10 = 0
fail = 0 ; fail10 = 0
while True :
  count = count+1 ; count10 = count10+1
  if count10 > 10 :
    count10=1 ; fail10=0
  #
  if exec(cmdln, 'assword:', 60) != 0 :
    fail=fail+1 ; fail10=fail10+1
  #
  thisTime = datetime.datetime.now(datetime.timezone.utc)
  thisTime = str(round((thisTime-startTime0).total_seconds()/60,2)) + "m"
  print("[ fail " + str(fail) + "/" + str(count) + " since past " + thisTime + " ] [ fail " + str(fail10) + "/" + str(count10) + " since past 10 attempts ]")
  print("sleeping ...")
  time.sleep(5)
#
