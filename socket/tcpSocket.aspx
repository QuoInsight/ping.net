<%@ Page language="C#" Debug="true"%>
<%@ Assembly Src="tcpSocket.cs" %>
<HTML>
<HEAD>
  <title>tcpSocket</title>
</HEAD>
<BODY>
<%
  string targetHost = Request["targetHost"];
  string targetPort = Request["targetPort"];
  string dataString = Request["dataString"];

  targetHost = (targetHost==null) ? "" : targetHost.Trim();
  targetPort = (targetPort==null) ? "" : targetPort.Trim();
  dataString = (dataString==null) ? "" : dataString.Trim();

  if (String.IsNullOrEmpty(targetHost)) targetHost = "www.google.com";
  if (String.IsNullOrEmpty(targetPort)) targetPort = "80";
  if (String.IsNullOrEmpty(dataString)) dataString = "GET /";
%>
  <form style='margin:0' method=post>
    <input type=text name="targetHost" size="20" value='<%=targetHost%>'>
    <input type=text name="targetPort" size="3" value='<%=targetPort%>'>
    <input type=text name="dataString" size="30" value='<%=Server.HtmlEncode(dataString)%>'>
    <input type=submit value="submit">
    <br><br>[response]<br>
    <%
      string respString = "";
      try {
        respString = myNameSpace.tcpSocket.sendData(targetHost, Convert.ToInt32(targetPort), dataString);
      } catch (Exception e) {
        respString += e.ToString() + "\n";
      }
    %>
    <textarea disabled name=responseText cols=120 rows=15
     ><%=Server.HtmlEncode(respString)%></textarea>
  </form>
</BODY>
</HTML>
