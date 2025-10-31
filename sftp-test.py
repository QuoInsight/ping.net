#!/usr/bin/env python3

import time
import datetime
import pexpect

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
#

sftp_o = "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
cmdln = "sftp " + sftp_o + " -P 2222 demo@demo.wftpserver.com"
cmdln = "sftp " + sftp_o + " demo@test.rebex.net"
while True :
  exec(cmdln, 'assword:', 5)
  print("sleeping ...")
  time.sleep(5)
#
