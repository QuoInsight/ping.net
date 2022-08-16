// [ https://docs.microsoft.com/en-us/dotnet/framework/network-programming/synchronous-client-socket-example ]

using System;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace myNameSpace {
  public class tcpSocket {

    public static string sendData(string targetHost, int targetPort, string dataString) {
      string respData = "";
      byte[] bytes = new byte[8192]; // Data buffer for incoming data.

      // Connect to a remote device.
      try {
        IPHostEntry ipHostInfo = Dns.GetHostEntry(targetHost);
        IPAddress ipAddress = ipHostInfo.AddressList[0];
        IPEndPoint remoteEP = new IPEndPoint(ipAddress, targetPort);
        Socket tcpSocket = new Socket(ipAddress.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
        tcpSocket.SendTimeout = 3000;
        tcpSocket.ReceiveTimeout = 3000;
        tcpSocket.ReceiveBufferSize = 8192;

        // Connect the socket to the remote endpoint. Catch any errors.
        try {
          tcpSocket.Connect(remoteEP);
          respData += "**connected** [" + tcpSocket.RemoteEndPoint.ToString() + "]\n";
          int bytesSent = tcpSocket.Send(Encoding.ASCII.GetBytes(dataString+"\n")); // Send the data through the socket.
          respData += "**sent** [" + dataString + "]\n";

          int bytesRcv=0, totalRcv=0;
          do {
            try {
              bytesRcv = tcpSocket.Receive(bytes, totalRcv, Convert.ToInt32(1024), System.Net.Sockets.SocketFlags.None); // Receive the response from the remote device.
            } catch(Exception e) {
              respData += "**receive aborted** [" + e.ToString() + "]\n";
              break;
            }
            totalRcv += bytesRcv;
          } while (bytesRcv > 0 && totalRcv < tcpSocket.ReceiveBufferSize);
          respData += "**received [" + totalRcv + " bytes]**\n";
          respData += Encoding.ASCII.GetString(bytes,0,totalRcv);
          try { tcpSocket.Shutdown(SocketShutdown.Both); } catch(Exception e) {}
          tcpSocket.Close();
        } catch (ArgumentNullException ane) {
          respData += "ArgumentNullException: " + ane.ToString() + "\n";
        } catch (SocketException se) {
          respData += "SocketException: " + se.ToString() + "\n";
          Console.WriteLine("SocketException : {0}",se.ToString());
        } catch (Exception e) {
          respData += "Unexpected exception: " + e.ToString() + "\n";
        }
      } catch (Exception e) {
        respData += e.ToString() + "\n";
      }
      return respData;
    } // Main()

  } // class
} // namespace
