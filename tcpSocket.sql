DECLARE
  l_reqData LONG;

  l_conn UTL_TCP.CONNECTION;
  l_rtnVal BINARY_INTEGER;
  l_respData LONG;

BEGIN

  --OPEN THE CONNECTION
  l_conn := UTL_TCP.OPEN_CONNECTION(
    REMOTE_HOST  => 'info.cern.ch',
    REMOTE_PORT  => 80,
    TX_TIMEOUT   => 10
  );

  l_reqData := 'GET / HTTP/1.0'||Chr(13)||Chr(10)||'Host: info.cern.ch'||Chr(13)||Chr(10)||Chr(13)||Chr(10);
  l_rtnVal := UTL_TCP.WRITE_LINE(l_conn, l_reqData);
  UTL_TCP.FLUSH(l_conn);

  -- CHECK AND READ RESPONSE FROM SOCKET
  BEGIN
    WHILE UTL_TCP.AVAILABLE(l_conn,10) > 0 LOOP
      l_respData := l_respData || UTL_TCP.GET_LINE(l_conn,TRUE);
      --EXIT; -- debug
    END LOOP;
  EXCEPTION
    WHEN UTL_TCP.END_OF_INPUT THEN NULL;
  END;
  UTL_TCP.CLOSE_CONNECTION(l_conn);

  Dbms_Output.put_line('response_data: '||substr(l_respData,1,240));

EXCEPTION
  WHEN OTHERS THEN RAISE_APPLICATION_ERROR(-20101,SQLERRM);
    UTL_TCP.CLOSE_CONNECTION(l_conn);
END;
