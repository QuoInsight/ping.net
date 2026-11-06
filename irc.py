#!/usr/bin/env python3

import socket, ssl, base64, sys
import time, datetime, re

# Configuration variables
SERVER = "irc.efnet.org"
PORT = 6697 ; SSL = True ; SASL = False
NICK = "?????" # std maxlen is 9chars
PASSW = None
CHANNEL = "#news"

def getCurrTime():
  return datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
#

def send(sck, msg):
  # IRC messages are always lines of characters terminated with CR-LF
  sck.send((msg+"\r\n").encode("utf-8"))
#

def main():
  # Create and connect the socket
  sck = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  if SSL :
    context = ssl.create_default_context()
    # --- BYPASS SELF-SIGNED CERTIFICATE ERROR ---
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
  #
  print(f">> Connecting to {SERVER}:{PORT}... ", end="")
  try:
    if SSL : sck = context.wrap_socket(sck, server_hostname=SERVER)
    sck.connect((SERVER, PORT))
  except Exception as e:
    print(f">> Connection failed: {e}")
    sys.exit(1)
  #
  print(">> connected.")

  REALNAME = NICK ; HOSTNAME = "0" ; SERVERNAME = "*"

  if SASL :
    print(">> sending SASL req... ", end="")
    send(sck, "CAP REQ :sasl")
    print(">> done")
  else :
    # Log in (Send identity information)
    print(">> logging in... ", end="")
    send(sck, f"USER {NICK} {HOSTNAME} {SERVERNAME} :{REALNAME}")
    send(sck, f"NICK {NICK}")
    print(">> sent")
  #

  # Buffer to store incoming stream data
  readbuffer = ""
  READY = False

  # Main loop to listen for data
  while True:
    try:
      # Receive up to 2048 bytes of data
      data = sck.recv(2048).decode("utf-8", errors="ignore")
      if not data:
        print(">> Disconnected from server.")
        break
      #

      readbuffer += data
      lines = readbuffer.split("\n")
      readbuffer = lines.pop()

      for line in lines:
        line = line.rstrip()

        # Automatically respond to PINGs from the server to keep connection alive
        if line.startswith("PING"):
          pong_resp = line.replace("PING", "PONG")
          send(sck, f"{pong_resp}")
          continue
        #

        m = re.search(r"^:\S+ (\d+)", line)
        nRpl = m.group(1) if m else None

        if not READY :

          if nRpl in ('001','002','003','004') :
            # skip 001 RPL_WELCOME 002 RPL_YOURHOST 003 RPL_CREATED 004 RPL_MYINFO
            continue
          elif nRpl == "372" :
            # skip RPL_MOTD
            continue
          #

          print(getCurrTime() + " " + line)

          if SASL :
            if "CAP" in line and "ACK :sasl" in line :
              print(">> initiate auth plain... ", end="")
              send(sck, "AUTHENTICATE PLAIN")
              print(">> sent")
              continue
            elif line.startswith("AUTHENTICATE +") :
              print(">> sending auth... ", end="")
              auth_str = f"\0{NICK}\0{PASSW}"
              auth_b64 = base64.b64encode(auth_str.encode("utf-8")).decode("utf-8")
              send(sck, f"AUTHENTICATE {auth_b64}")
              print(f">> sent {NICK}")
              continue
            elif nRpl == "903" :
              print(">> completing auth... ", end="")
              send(sck, "CAP END")
              send(sck, f"USER {NICK} {HOSTNAME} {SERVERNAME} :{REALNAME}")
              send(sck, f"NICK {NICK}")
              print(">> done login.")
              continue
            elif nRpl in ('904', '905') :
              print("Abort! SASL Authentication Failed")
              send(sck, "QUIT")
              break
            #
          #

          if nRpl in ('376', '422') :
            # Join the channel once the server sends the welcome message (End of MOTD code 376)
            if not(SASL) and PASSW :
              print(">> sending NickServ identify... ", end="")
              send(sck, f"PRIVMSG NickServ :IDENTIFY {PASSW}")
              print(">> done")
              time.sleep(2)
            #

            if CHANNEL :
              print(f"\n>> Joining channel {CHANNEL}... ", end="")
              send(sck, f"JOIN {CHANNEL}")
              print(">> sent. [" + getCurrTime() + "]")

              time.sleep(1)
              send(sck, f"CHATHISTORY LATEST {CHANNEL} timestamp 10")
              print(f">> sent: CHATHISTORY LATEST {CHANNEL}")

              #MSG = "Hi, everyone!"
              #send(sck, f"PRIVMSG {CHANNEL} :{MSG}")
              #print(f">> sent: {$MSG}")
              continue
            #
            READY = True
          #

        # not READY

        # Filter and print channel messages (PRIVMSG)
        if "PRIVMSG" in line :
          # Parse username and message content
          parts = line.split(":", 2)
          if CHANNEL in line:
            if len(parts) >= 3:
              user = parts[1].split("!")[0]
              message = parts[2]
              print(getCurrTime())
              print(f"[{CHANNEL}] <{user}> {message}")
              continue
            #
          #
          print(getCurrTime() + " " + line)
          if "\x01VERSION\x01" in line :
            if len(parts) >= 2:
              probing_user = parts[0].split("!")[0].lstrip(":")
              VERSION = "irc.py 0.0.1 [x64] on Linux (Ubuntu 24.04)"
              send(sck, f"NOTICE {probing_user} :\x01VERSION {VERSION}\x01")
              print(">> replied.")
            #
          #
        elif READY :
          if nRpl == "353" :
            # skip RPL_NAMREPLY default /NAMES list of connected users
            continue
          else :
            print(getCurrTime() + " " + line)
          #
        #

      # for line

    except KeyboardInterrupt:
      # Safely exit on Ctrl+C
      print("\n>> Disconnecting...")
      send(sck, f"QUIT :Exiting bot")
      sck.close()
      break
    # main try
  # while
# main

if __name__ == "__main__":
  main()
#
