/*
  © (ɔ) QuoInsight
*/
using System;
using System.Runtime.InteropServices; // DllImport
using System.Net.NetworkInformation;
using System.Management;

namespace myNameSpace {
  class myClass {
    public static bool consoleCancelled = false;
    public static string targetHost="", nicInfo="", logFile="pingsckt.log";
    public static int targetPort=80, timeout=2000;
    public static DateTime startTime = DateTime.Now;
    public static long i=0, pingCount=1800, responseCount=0, responseTime=0, totalResponseTime=0, minResponseTime=-1, maxResponseTime=0;

    static void println(string txt) {
      string errMsg = "";
      try { Console.WriteLine(txt); } catch(Exception e) { errMsg = e.Message; }
      try { if (logFile!="") using (System.IO.StreamWriter w = System.IO.File.AppendText(logFile)) w.WriteLine(txt);
      } catch(Exception e) { errMsg = e.Message; }
      try { if (errMsg!="") Console.Error.WriteLine(errMsg); } catch(Exception e) { errMsg = e.Message; }
    }

    static void printSummary() {
      println("");  if (nicInfo!="") println(nicInfo);
      println(
        "Target:" + targetHost + ":" + targetPort + " Duration:" + startTime.ToString("yyyy-MM-dd HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture)
        + " - " + DateTime.Now.ToString("HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture) + "\n"
        + "Reply:" + responseCount + "/" + i + " (" + Math.Round((double)100*(i-responseCount)/i) + "% loss) "
        + "Min:" + minResponseTime + "ms Max:" + maxResponseTime + "ms Avg:" + Math.Round((double)totalResponseTime/responseCount) + "ms"
      );
      return;
    }

    static void myConsoleCancelEventHandler(object sender, ConsoleCancelEventArgs args) {
      // Set the Cancel property to true to prevent the process from terminating.
      // Console.WriteLine("The operation will resume...\n");
      args.Cancel = true;
      consoleCancelled = true;
      return;
    }

    [DllImport("Kernel32")] public static extern bool SetConsoleCtrlHandler(HandlerRoutine handler, bool Add);
    public delegate bool HandlerRoutine(CtrlTypes CtrlType);
    public static HandlerRoutine myConsoleCtrlHandler;  // will need this as static to keep it for final garbage collector [ http://stackoverflow.com/questions/6783561/nullreferenceexception-with-no-stack-trace-when-hooking-setconsolectrlhandler ]
    public enum CtrlTypes {
      CTRL_C_EVENT=0, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT,
      CTRL_LOGOFF_EVENT=5, CTRL_SHUTDOWN_EVENT
    }
    static bool myConsoleCtrlHandlerCallbackFunction(CtrlTypes ctrlType) {
      consoleCancelled = true;
      switch (ctrlType) {
        case CtrlTypes.CTRL_C_EVENT:
          Console.Error.WriteLine("^CTRL_C_EVENT"); break;
        case CtrlTypes.CTRL_BREAK_EVENT:
          Console.Error.WriteLine("^CTRL_BREAK_EVENT"); break;
        case CtrlTypes.CTRL_CLOSE_EVENT:
          Console.Error.WriteLine("^CTRL_CLOSE_EVENT"); break;
        case CtrlTypes.CTRL_LOGOFF_EVENT:
          Console.Error.WriteLine("^CTRL_LOGOFF_EVENT"); break;
        case CtrlTypes.CTRL_SHUTDOWN_EVENT:
          Console.Error.WriteLine("^CTRL_SHUTDOWN_EVENT"); break;
      }
      //i++;  nicInfo=getNicInfo();  printSummary();
      System.Threading.Thread.Sleep(30000); // 3000
      System.Environment.Exit(1);
      return true; // If the function handles the control signal, it should return TRUE
    }

    ////////////////////////////////////////////////////////////////////

    static void Main(string[] args) {

      if (args.Length > 0) targetHost = args[0];
      if (args.Length > 1) int.TryParse(args[1], out targetPort);
      if (args.Length > 2) long.TryParse(args[2], out pingCount); // Convert.ToInt64(args[2]);
      if (args.Length > 3) logFile = args[3];  if (logFile=="-") logFile="";

      if (targetHost=="/?" || targetHost=="-?" || targetHost=="?" || targetHost=="/h" || targetHost=="-h" || targetHost=="/help" || targetHost=="-help") {
        Console.Error.WriteLine();
        Console.Error.WriteLine("Syntax: ping.net.exe [ipAddr/hostName [port [count [logFile]]]]");  // args[0] args[1]
        Console.Error.WriteLine("Default: ping.net.exe <defaultGateway> 80 1800 pingsckt.log");  // args[0] args[1]
        Console.Error.WriteLine();
        return;
      }

      nicInfo = getNicInfo();
      if (targetHost=="") {
        var m = (new System.Text.RegularExpressions.Regex(@" GW:(\S+)")).Match(nicInfo);
        targetHost = (m.Success) ? (m.Groups[1]).ToString() : System.Net.IPAddress.Loopback.ToString();
      }
      if (targetHost=="") targetHost=System.Net.IPAddress.Loopback.ToString();
      println("");  if (nicInfo!="") println(nicInfo);

      //Console.CancelKeyPress += new ConsoleCancelEventHandler(myConsoleCancelEventHandler);
      myConsoleCtrlHandler = new HandlerRoutine(myConsoleCtrlHandlerCallbackFunction); // will need to keep this in a static var for final garbage collector [ http://stackoverflow.com/questions/6783561/nullreferenceexception-with-no-stack-trace-when-hooking-setconsolectrlhandler ]
      SetConsoleCtrlHandler(myConsoleCtrlHandler, true);

      System.Collections.Queue last20Queue = new System.Collections.Queue();

      for ( i=0; (pingCount==-1 || i < pingCount); i++ ) {
        if (consoleCancelled) break; 
        if (i>0) System.Threading.Thread.Sleep(1000) ;
        var statusCode = ": ";
        responseTime = connectSocket(targetHost, targetPort, timeout);  if (responseTime > -1) {
          responseCount++;
          last20Queue.Enqueue(1);
          totalResponseTime += responseTime;
          if (minResponseTime < 0 || responseTime < minResponseTime) minResponseTime = responseTime;
          if (responseTime > maxResponseTime) {
            maxResponseTime = responseTime;
            statusCode = "^^";
          }
          if (responseTime > Math.Round((double)totalResponseTime/responseCount)) statusCode = "^ ";
        } else {
          statusCode = "^^";
          last20Queue.Enqueue(0);
        }
        if (last20Queue.Count > 20) last20Queue.Dequeue();
        int last20Pass=0; foreach(int item in last20Queue) last20Pass+=item;
        Console.Write(string.Format("{0:00}{1}", 100*(last20Queue.Count-last20Pass)/last20Queue.Count, statusCode));
      }

      nicInfo=getNicInfo();  printSummary();
      if (consoleCancelled) try {
        Console.Error.WriteLine("terminating... press <enter> to exit immediately.");
        String line = Console.ReadLine();
      } catch(Exception e) { var errMsg = e.Message; }

      return;
    } // Main()

    ////////////////////////////////////////////////////////////////////

    public static long connectSocket(string targetHost, int targetPort, int timeout) {
      bool validIpAddr = true;
      DateTime startTime = DateTime.Now;
      System.Net.IPAddress ipAddress = null;
      try {
        ipAddress = System.Net.IPAddress.Parse(targetHost);
      } catch(Exception e) {
        if (e is ArgumentNullException || e is FormatException) {
          validIpAddr = false;
        } else {
          Console.Error.WriteLine(e.ToString().Split('\n')[0]); // e.Message
          return -1;
        }
      }
      if (! validIpAddr) try {
        System.Net.IPHostEntry hostEntry = System.Net.Dns.GetHostEntry(targetHost);
        ipAddress = hostEntry.AddressList[0];
      } catch(Exception e) {
        Console.Error.WriteLine(e.ToString().Split('\n')[0]); // e.Message
        return -1;
      }
      if (targetPort > 0) { // TCP Port
        System.Net.Sockets.Socket socket = new System.Net.Sockets.Socket(System.Net.Sockets.AddressFamily.InterNetwork, System.Net.Sockets.SocketType.Stream, System.Net.Sockets.ProtocolType.Tcp);
        try {
          //socket.Connect(ipAddress, targetPort);
          IAsyncResult result = socket.BeginConnect(ipAddress, targetPort, null, null);
          bool success = result.AsyncWaitHandle.WaitOne(2000, true);
        } catch(Exception e) {
          Console.Error.WriteLine(e.ToString().Split('\n')[0]); // e.Message
          return -1;
        }
        if (socket.Connected) {
          var ttl = socket.Ttl;
          socket.Close();  var responseTime = Math.Round((double)( (DateTime.Now.Ticks - startTime.Ticks) / TimeSpan.TicksPerMillisecond ),0);
          println(
            DateTime.Now.ToString("HH:mm:ss.fff", System.Globalization.CultureInfo.InvariantCulture) // "yyyy-MM-dd"
             + " Connected to " + ipAddress + ":" + targetPort + " time=" + responseTime + "ms TTL=" + ttl
          );
          return (long)responseTime;
        } else {
          try {
            socket.Close();
          } catch {}
          println(DateTime.Now.ToString("HH:mm:ss.fff ", System.Globalization.CultureInfo.InvariantCulture) + "TimedOut / Failed to connect [" + ipAddress + ":" + targetPort + "]");
          return -1;
        }
      } else { // UDP Port
        System.Net.IPEndPoint ipEndPoint = new System.Net.IPEndPoint(ipAddress, Math.Abs(targetPort));
        System.Net.Sockets.Socket socket = new System.Net.Sockets.Socket(ipEndPoint.AddressFamily, System.Net.Sockets.SocketType.Dgram, System.Net.Sockets.ProtocolType.Udp);
        try {
          int pingSize = 32;
          byte[] bytes = new byte[pingSize];
          socket.SendTo(bytes, ipEndPoint);
          var ttl = socket.Ttl;
          socket.Close();  var responseTime = Math.Round((double)( (DateTime.Now.Ticks - startTime.Ticks) / TimeSpan.TicksPerMillisecond ),0);
          println(
            DateTime.Now.ToString("HH:mm:ss.fff", System.Globalization.CultureInfo.InvariantCulture) // "yyyy-MM-dd"
             + " Sent to " + ipAddress + ":" + targetPort + " bytes=" + pingSize + " time=" + responseTime + "ms TTL=" + ttl
          );
          return (long)responseTime;
        } catch(Exception e) {
          Console.Error.WriteLine(e.ToString().Split('\n')[0]); // e.Message
          return -1;
        }
      }

    } // ping|connectSocket()

    ////////////////////////////////////////////////////////////////////

    public static string getNicInfo() {
      string nicInfo="", macAddr="";
      bool foundDefaultGateway = false;
      try {
        foreach (var nic in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces()) {
          if ( nic.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up
            && (nic.NetworkInterfaceType == System.Net.NetworkInformation.NetworkInterfaceType.Wireless80211
                 || nic.NetworkInterfaceType == System.Net.NetworkInformation.NetworkInterfaceType.Ethernet)
          ) {
            macAddr = nic.GetPhysicalAddress().ToString();
            nicInfo = Environment.MachineName + " [" + nic.Name + "] Type:" + nic.NetworkInterfaceType + " MAC:" + macAddr + "\n";
            if (nic.NetworkInterfaceType.ToString().IndexOf("Wireless")==0) {
              nicInfo += " " + getConnectedSsidNetsh(macAddr); // Windows.Networking.Connectivity.GetConnectedSsid();
            }
            var props = nic.GetIPProperties();  if (props == null) {
              continue;
            } else {
              foreach (var ip in props.UnicastAddresses) {
                if (ip.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork) {
                  nicInfo += " IP:" + ip.Address.ToString();
                  //break;
                }
              }
              foreach (var gwAddrInfo in props.GatewayAddresses) {
                var gwAddr = gwAddrInfo.Address;
                if (gwAddr.AddressFamily==System.Net.Sockets.AddressFamily.InterNetwork && !gwAddr.ToString().Equals("0.0.0.0")) {
                  nicInfo += " GW:" + gwAddr.ToString();
                  foundDefaultGateway = true;
                  //break;
                }
              }
              if (foundDefaultGateway) break;
            } // props
          } // nic
        } // GetAllNetworkInterfaces
      } catch(Exception e) { return "getNicInfo(): " + e.Message; }
      return nicInfo;
    }

    /*
      !!! Native Wifi application programming interface (API) / Wlan API [Wlanapi.h / Wlanapi.dll]
      can't be directly referenced in C#. You must marshall everything yourself using P/Invoke.
      That takes a lot of work. !!!
    */

    static string getTextAfterFirstColon(string txt) {
      return System.Text.RegularExpressions.Regex.Replace(txt, @"^([^:]*:\s*)", "");
    }

    static string getConnectedSsidNetsh(string macAddr) {
      string ssid = "";
      try {
        var process = new System.Diagnostics.Process {
          StartInfo = {
            FileName = "netsh.exe",
            Arguments = "wlan show interfaces",
            WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            CreateNoWindow = true
          }
        };  process.Start();
        var output = process.StandardOutput.ReadToEnd();
        bool foundMacAddr = false;
        foreach( var line in output.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries) ) {
          if (foundMacAddr) {
            if ( line.Contains("BSSID") ) {
              ssid += " BSSID:" + getTextAfterFirstColon(line.Trim()).Replace(":","");
            } else if ( line.Contains("SSID") ) {
              ssid += getTextAfterFirstColon(line.Trim());  // line.Split(new[]{":"}, StringSplitOptions.RemoveEmptyEntries)[1].Trim();
            } else if ( line.IndexOf("Signal", StringComparison.OrdinalIgnoreCase) > 0 ) {
              ssid += " [" + getTextAfterFirstColon(line.Trim()) + "]";
              break;
            }
            //return line.Split(new[]{":"}, StringSplitOptions.RemoveEmptyEntries)[1].TrimStart();
          } else {
            foundMacAddr = ( line.ToUpper().Replace(":","").Replace("-","").IndexOf(macAddr) > 0 );
          }
        }
      } catch(Exception e) { return "getConnectedSsidNetsh(): " + e.Message; }
      return ssid;
    }

  } // myClass
} // myNameSpace

