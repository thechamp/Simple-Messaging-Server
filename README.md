Simple-Messaging-Server
=======================

This is a simple TCP messaging server which handles registration, authentication and message sending from clients.

Commands
--------
 - *tag* **REGISTER** {number} {password} {name}
 - *tag* **AUTH** {number} {password}
 - *tag* **SELECT** {folder} (here folder can be INBOX or SENT)
 - *tag* **FETCH**
 - *tag* **FETCH AFTER DATE** {date}
 - *tag* **FETCH AFTER ID** {id}
 - *tag* **SEND** {number} {message}
 - *tag* **BYE**

How to start server
-------------
call following command from erlang shell to start the TCP server.  

```erlang
tcp_server:start_server().
```

How to run test client
-------------------
call following command from erlang shell after starting the TCP server.  

```erlang
test_client:start().
```

This will start sample client module filled with few commands. The output of each command will be visible on shell.