
svcAddr = '127.0.0.1' ## http://127.0.0.01:8080
svcPort = 8080 ## netstat -a -n -o | find "8080"
upstrmServer = "192.168.43.1"
upstrmPort = 80
httpContent = True

import socket
import datetime

def printHeadTail(data, excerptLength) :
  tailEnd = len(data)
  tailStart = (tailEnd-excerptLength) if (tailEnd>=excerptLength) else 0
  if tailStart>0 : print(repr(data[0:tailEnd-tailStart]))
  print(repr(data[tailStart:tailEnd]))
#

if __name__ == '__main__':
  tcpSockTyp = socket.SOCK_STREAM ## udp: socket.SOCK_DGRAM | tcp:socket.SOCK_STREAM
  if True :
  #try:
    svcSock = socket.socket(socket.AF_INET, tcpSockTyp)
    print("starting "+svcAddr+":"+str(svcPort)+" ... "+str(svcSock.type))
    svcSock.bind((svcAddr, svcPort))  ## netstat -ano | findstr 53
    svcSock.listen(2)
    while True:
      clientSock, clientAddr = svcSock.accept(); 
      clientSock.settimeout(1)
      dataAll = b""
      try:
        chnkSz = 4096
        while True:
          data = clientSock.recv(chnkSz)
          if (not data) or len(data)==0 : break
          dataAll = dataAll + data
          #if (len(data)<chnkSz) : break
          if httpContent and data.endswith(b"\r\n\r\n") : break
        #
      except Exception as e:
        print(e)
      #
      print(
        "\n" + datetime.datetime.now().strftime("%H:%M:%S")
        + " [svcSock:recv] " + str(clientAddr)
        + " (" + str(len(dataAll)) + " bytes)..."
      )
      printHeadTail(dataAll, 50)
      #print(repr(dataAll))

      with socket.socket(socket.AF_INET, tcpSockTyp) as upstrmSock :
        upstrmSock.connect((upstrmServer, upstrmPort))
        upstrmSock.settimeout(5)
        upstrmSock.sendall(dataAll)
        upstrmRspAll = b""
        try:
          chnkSz = 4096
          headerEnd = -1
          contentLength = -1
          while True:
            upstrmRsp = upstrmSock.recv(chnkSz)
            if (not upstrmRsp) or len(upstrmRsp)==0 : break
            upstrmRspAll = upstrmRspAll + upstrmRsp

            if httpContent and (headerEnd < 0) :
              headerEnd = upstrmRspAll.find(b"\r\n\r\n")
              if (headerEnd > 0) :
                headerEnd = headerEnd + 4
                print(" **** headerEnd : "+str(headerEnd))
                header = upstrmRspAll[0:headerEnd].decode("utf8")
                contentLength = header.lower().find("content-length:")
                if (contentLength > 0) :
                  contentLength = header[contentLength+15:header.find("\r\n",contentLength)]
                  print(" *** contentLength: "+str(contentLength))
                  contentLength = int(contentLength)
                #
              #
            #
            #if (len(upstrmRsp)<chnkSz) : break
            if httpContent :
              if upstrmRsp.endswith(b"\r\n\r\n") : break
              if contentLength>0 and len(upstrmRspAll)>=(headerEnd+contentLength) : break
            #
          #
        except Exception as e:
          print(e)
        #
        print(
          datetime.datetime.now().strftime("%H:%M:%S")
          + " [upstrmSock:recv] " + str(upstrmServer) + ":" + str(upstrmPort)
          + " (" + str(len(upstrmRspAll)) + " bytes)..."
        )
        printHeadTail(upstrmRspAll, 50)
        #print(repr(upstrmRspAll))

        ##upstrmRsp = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\n\nOK"
        clientSock.sendall(upstrmRspAll);
      #
      clientSock.close()
    #
  #except Exception as e:
  #  print(e)
  #  svcSock.close()
  #
#

