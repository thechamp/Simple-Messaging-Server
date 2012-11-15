%%%-------------------------------------------------------------------
%%% @author  Abhay Jain <abhay_1303@yahoo.co.in>
%%% @doc  This module is TCP/IP server which listens on specified port,
%%%       accepts connections and spawns a new process for each socket
%%%       connection. The process receives all messages of that socket.
%%% @end
%%% Created :  10 Nov 2012 by  Abhay Jain
%%%-------------------------------------------------------------------
-module(tcp_server).

%% API
-export([
	 start_server/0
	]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc  This method is called to start TCP server
%% @spec start_server() -> ok
%% @end
%%--------------------------------------------------------------------
start_server() ->
    io:format("Starting TCP server on port 8091~n", []),
    case gen_tcp:listen(8091, [{active, false}, {packet, 0}]) of
	{ok, Socket} ->
	    io:format("Server was successfully started at socket ~p~n", [Socket]),
	    %% Start the mnesia database and create tables
	    sessions_manager:start(),
	    
	    %% Spawn process to receive connection requests
	    spawn(fun() ->
			  accept_connection(Socket)
		  end),
	    ok;
	{error, Reason} ->
	    io:format("Server could not be started because ~p~n", [Reason])
    end.


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc  This method is waiting for clients to connect to server
%% @spec accept_connection(Socket::socket()) -> pid()
%% @end
%%--------------------------------------------------------------------
accept_connection(Socket) ->
    io:format("Waiting for new connection~n", []),
    case gen_tcp:accept(Socket) of
	{ok, ClientSocket} ->
	    io:format("New TCP connection established with a client on socket ~p~n", [ClientSocket]),
	    %% Feed this Socket in active sessions list of mnesia database
	    sessions_manager:start_new_session(ClientSocket),
	    
	    %% Spawn a separate process to receieve data on this socket
	    spawn(fun() ->
			  receive_data(ClientSocket)
		  end);
	{error, Reason} ->
	    io:format("Connection could not be established because ~p~n", [Reason])
    end,
    %% Go in waiting mode again to receive connection requests
    accept_connection(Socket).

%%--------------------------------------------------------------------
%% @doc  This funtion is spawned as individual process whenever a new
%%       client connects.
%% @spec  receive_data(Socket::socket()) -> ok | pid()
%% @end
%%--------------------------------------------------------------------
receive_data(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, RawData} ->
	    Data = trim_data(RawData),
	    io:format("Received data ~p on socket ~p~n", [Data, Socket]),
	    Tokens = string:tokens(Data, " "),
	    
	    if length(Tokens) == 0 ->
		    %% Data is empty, and has no tag
		    %% Send error with "*" tag
		    sessions_manager:send_reply(Socket, "*", "BAD");
	       length(Tokens) < 2 ->
		    %% Data from client should have atleast two words
		    %% Every data should atleast have a tag and a command
		    sessions_manager:send_reply(Socket, lists:nth(1, Tokens), "BAD");
	       true ->
		    %% Identify the command and call appropriate function
		    case lists:nth(2, Tokens) of
			"REGISTER" ->
			    sessions_manager:register_new_user(Socket, Tokens);
			"AUTH" ->
			    sessions_manager:try_user_auth(Socket, Tokens);
			"SELECT" ->
			    sessions_manager:select_folder(Socket, Tokens);
			"FETCH" ->
			    sessions_manager:fetch_messages(Socket, Tokens);
			"SEND" ->
			    sessions_manager:send_message(Socket, Tokens);
			"BYE" ->
			    sessions_manager:quit_session(Socket, Tokens);
			_ ->
			    %% Unknown command
			    sessions_manager:send_reply(Socket, lists:nth(1, Tokens), "BAD")
		    end
	    end,
	    %% After processing the current data, go in waiting mode again
            receive_data(Socket);
        {error, closed} ->
            ok
    end.

trim_data(RawData) ->
    %% Strip carriage-return from Raw Data
    Data1 = string:strip(RawData, both, $\n),
    string:strip(Data1, both, $\r).
