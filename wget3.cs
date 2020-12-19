using System;

namespace myNamespace {
  public class myClass {
  
    ////////////////////////////////////////////////////////////////////
    
    public static string wget3(string pUrl, string pMethod, string[] pHeaders, byte[] pData, int pTimeout) {
      string method=pMethod.ToUpper(), postURL="", postData="", responseText="";
      System.IO.Stream strm;
      int p;

      if (method.Length==0) method="GET";

      if ( String.Equals(method, "POST") && (pData==null||pData.Length==0) ) {
        p = pUrl.IndexOf("?"); if (p > 0) {
          postURL=pUrl.Substring(0, p);  postData=pUrl.Substring(p+1);
        } else {
          postURL=pUrl;  postData="";
        }
      } else {
        postURL = pUrl;
      }

      System.Net.HttpWebRequest wbRqst = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(postURL);
        // wbRqst.Proxy = new System.Net.WebProxy("localhost", 1080);
        /* 
          if ( pProxy != null && pProxy.Length > 0 ) {
            string[] prxy = pProxy.Split(':');
            wbRqst.Proxy = new System.Net.WebProxy(prxy[0], Convert.ToInt32(prxy[1]));
          }
          // we trust what we are doing here. this will avoid [ System.Security.Authentication.AuthenticationException: The remote certificate is invalid according to the validation procedure. ]
          System.Net.ServicePointManager.ServerCertificateValidationCallback += delegate(object sender,
            System.Security.Cryptography.X509Certificates.X509Certificate certificate,
            System.Security.Cryptography.X509Certificates.X509Chain chain,
            System.Net.Security.SslPolicyErrors sslPolicyErrors
          ) { return true; };  // Always accept/pass the validation !
        */

        wbRqst.Method = method;
        if (pTimeout > 0) wbRqst.Timeout = pTimeout * 1000;

        //wbRqst.UserAgent = "Mozilla/4.0 (compatible; Win32; WinHttp.WinHttpRequest.5)";
        //wbRqst.Accept = "*/*";  wbRqst.Headers.Add("Accept-Language", "en-US");
        if (pHeaders != null) {
          string h="", v="";  foreach (string h1 in pHeaders) {
            h=h1;  v="";  p=h1.IndexOf(":");  if (p >= 0) {
              v=h1.Substring(p+1).Trim();  h=h1.Substring(0, p).Trim();
            }
            //System.Web.HttpContext.Current.Response.Write("\n<br>\n" + h + "\n<br>\n" + v + "\n<br>\n");
            switch ( h.ToLower() ) {
              case "content-type" :
                wbRqst.ContentType = v;
                break;
              default :
                wbRqst.Headers.Add(h, v);
                break;
            }
          }
        }
        /*
          // System.Collections.Generic.Dictionary<string, string> pHeaders
          foreach (System.Collections.Generic.KeyValuePair<string, string> entry in pHeaders) {
            wbRqst.Headers.Add(entry.Key, entry.Value);
          }
        */

      try {
        if ( String.Equals(method, "POST")||String.Equals(method, "PUT") ) {
          byte[] byteArr = System.Text.Encoding.UTF8.GetBytes(postData);
          if (byteArr.Length > 0) {
            wbRqst.ContentType = "application/x-www-form-urlencoded";
          } else if (pData!=null) {
            byteArr = pData;
          }
          wbRqst.ContentLength = byteArr.Length;
          strm = wbRqst.GetRequestStream();
          strm.Write(byteArr, 0, byteArr.Length);
          strm.Close();
        }
        System.Net.HttpWebResponse wbRspn = (System.Net.HttpWebResponse)wbRqst.GetResponse();
          strm = wbRspn.GetResponseStream();
            System.IO.StreamReader strmRdr = new System.IO.StreamReader(strm);
            responseText = strmRdr.ReadToEnd();
            strmRdr.Close();
          strm.Close();
          if ( (int)wbRspn.StatusCode != 200 ) {
            return "<ERR/>HTTP " + wbRspn.StatusDescription + "\n" + responseText;
          }
          wbRspn.Close();
      } catch(Exception e) {
        return "<ERR/>" + e.Message;
        //Response.Write("Error: [" + e.GetType().AssemblyQualifiedName + "] [" + e.Source + "] [" + e.Message + "] [" + e.StackTrace + "]");
        //Response.Write("Error: " + e.ToString());
      }

      return responseText;
    }
    
    ////////////////////////////////////////////////////////////////////

  }
}
