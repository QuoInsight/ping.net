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
    public static int timeout=2000;
    public static string pingTarget="", nicInfo="", logFile="ping.net.log";
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
        "Target:" + pingTarget + " Duration:" + startTime.ToString("yyyy-MM-dd HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture)
        + " - " + DateTime.Now.ToString("HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture) + "\n"
        + "Reply:" + responseCount + "/" + i + " (" + Math.Round((double)100*(i-responseCount)/i) + "% loss) "
        + "Min:" + minResponseTime + "ms Max:" + maxResponseTime + "ms Avg:" + Math.Round((double)totalResponseTime/responseCount) + "ms"
      );
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

    static void Main(string[] args) {

      if (args.Length > 0) pingTarget = args[0];
      if (args.Length > 1) long.TryParse(args[1], out pingCount); // Convert.ToInt64(args[1]);
      if (args.Length > 2) logFile = args[2];  if (logFile=="-") logFile="";

      if (pingTarget=="/?" || pingTarget=="-?" || pingTarget=="?" || pingTarget=="/h" || pingTarget=="-h" || pingTarget=="/help" || pingTarget=="-help") {
        Console.Error.WriteLine();
        Console.Error.WriteLine("Syntax: ping.net.exe [ipAddr/hostName [count [logFile]]]");  // args[0] args[1]
        Console.Error.WriteLine("Default: ping.net.exe <defaultGateway> 1800 ping.net.log");  // args[0] args[1]
        Console.Error.WriteLine();
        return;
      }

      nicInfo = getNicInfo();
      if (pingTarget=="") {
        var m = (new System.Text.RegularExpressions.Regex(@" GW:(\S+)")).Match(nicInfo);
        pingTarget = (m.Success) ? (m.Groups[1]).ToString() : System.Net.IPAddress.Loopback.ToString();
      }
      if (pingTarget=="") pingTarget=System.Net.IPAddress.Loopback.ToString();
      println("");  if (nicInfo!="") println(nicInfo);

      myConsoleCtrlHandler = new HandlerRoutine(myConsoleCtrlHandlerCallbackFunction); // will need to keep this in a static var for final garbage collector [ http://stackoverflow.com/questions/6783561/nullreferenceexception-with-no-stack-trace-when-hooking-setconsolectrlhandler ]
      SetConsoleCtrlHandler(myConsoleCtrlHandler, true);

      for ( i=0; (pingCount==-1 || i < pingCount); i++ ) {
        if (consoleCancelled) break; 
        if (i>0) System.Threading.Thread.Sleep(1000) ;
        responseTime = ping(pingTarget, timeout);  if (responseTime > -1) {
          responseCount++;
          totalResponseTime += responseTime;
          if (minResponseTime < 0 || responseTime < minResponseTime) minResponseTime = responseTime;
          if (responseTime > maxResponseTime) maxResponseTime = responseTime;
        }
      }

      nicInfo=getNicInfo();  printSummary();
      if (consoleCancelled) try {
        Console.Error.WriteLine("terminating... press <enter> to exit immediately.");
        String line = Console.ReadLine();
      } catch(Exception e) { var errMsg = e.Message; }

      return;
    } // Main()

    public static long ping(string pingTarget, int timeout) {
      // Ping's the local machine.
      System.Net.NetworkInformation.Ping pingSender = new System.Net.NetworkInformation.Ping();
      System.Net.NetworkInformation.PingReply reply;
      try {
        reply = pingSender.Send(pingTarget, timeout);
      } catch(Exception e) {
        Console.Error.WriteLine(e.ToString().Split('\n')[0]); // e.Message
        return -1;
      }
      if (reply.Status == System.Net.NetworkInformation.IPStatus.Success) {
        println(
          DateTime.Now.ToString("HH:mm:ss.fff", System.Globalization.CultureInfo.InvariantCulture) // "yyyy-MM-dd"
           + " Reply from " + reply.Address.ToString() + ": bytes=" + reply.Buffer.Length
           + " time=" + reply.RoundtripTime + "ms TTL=" + reply.Options.Ttl
        );
        //Console.WriteLine("Don't fragment: {0}", reply.Options.DontFragment);
        return reply.RoundtripTime;
      } else {
        println(DateTime.Now.ToString("HH:mm:ss.fff ", System.Globalization.CultureInfo.InvariantCulture) + reply.Status.ToString());
        return -1;
      }
    } // ping()

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

    // Ref: http://stackoverflow.com/questions/431755/get-ssid-of-the-wireless-network-i-am-connected-to-with-c-sharp-net-on-windows
    
    static string getConnectedSsidWMI() {
      System.Management.ManagementObjectSearcher searcher = new System.Management.ManagementObjectSearcher(
        "root\\WMI", "SELECT * FROM MSNdis_80211_ServiceSetIdentifier"
      );
      foreach (System.Management.ManagementObject queryObj in searcher.Get()) {
        if( queryObj["Ndis80211SsId"] != null ) {
          Byte[] arrNdis80211SsId = (Byte[])(queryObj["Ndis80211SsId"]);
          string ssid = "";
          foreach (Byte arrValue in arrNdis80211SsId) {
            ssid += arrValue.ToString();
          }
          return ssid;
        }
      }
      return "";
    }

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
              ssid += getTextAfterFirstColon(line.Trim());
            } else if ( line.IndexOf("Signal", StringComparison.OrdinalIgnoreCase) > 0 ) {
              ssid += " [" + getTextAfterFirstColon(line.Trim()) + "]";
              break;
            }
          } else {
            foundMacAddr = ( line.ToUpper().Replace(":","").Replace("-","").IndexOf(macAddr) > 0 );
          }
        }
      } catch(Exception e) { return "getConnectedSsidNetsh(): " + e.Message; }
      return ssid;
    }

  } // myClass
} // myNameSpace
