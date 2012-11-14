%%%-------------------------------------------------------------------
%%% @author  Abhay Jain <abhay_1303@yahoo.co.in>
%%% @doc This module is a test client module which contains some
%%%      arbitrary commands to test on tcp_server.erl module
%%% @end
%%% Created : 10 Nov 2012 by  Abhay Jain
%%%-------------------------------------------------------------------
-module(test_client).

%% API
-export([
	 start/0
	]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
start() ->
    spawn(fun() ->client_p() end),
    spawn(fun() ->client_q() end).

client_p() ->
    %% Starting a client P
    {ok, P} = gen_tcp:connect({127,0,0,1}, 8091, [{active, false}, {packet, 0}]),
    
    %% Invalid auth
    gen_tcp:send(P, "tagp1 AUTH 1234 pwd"),
    receive_data(P),

    %% valid Registeration
    gen_tcp:send(P, "tagp2 REGISTER 0123456789 pwd abhay jain"),
    receive_data(P),

    %% Registering same number again
    gen_tcp:send(P, "tagp3 REGISTER 0123456789 pwd abhay jain"),
    receive_data(P),

    %% Valid Auth
    gen_tcp:send(P, "tagp4 AUTH 0123456789 pwd"),
    receive_data(P),

    %% Send msg
    gen_tcp:send(P, "tagp5 SEND 1234567890 hello my friend!"),
    receive_data(P),

    %% send msg
    gen_tcp:send(P, "tagp6 SEND 1234567890 How r u!"),
    receive_data(P),

    %% Fecth without select command
    gen_tcp:send(P, "tagp7 FETCH OUTBOX"),
    receive_data(P),
    
    %% Issue select command
    gen_tcp:send(P, "tagp8 SELECT INBOX"),
    receive_data(P),

    %% Fecth selected folder
    gen_tcp:send(P, "tagp9 FETCH"),
    receive_data(P),

    %% fetch with id cursor
    gen_tcp:send(P, "tagp10 FETCH AFTER ID 1"),
    receive_data(P),

    %% fetch with date cursor
    gen_tcp:send(P, "tagp11 FETCH AFTER DATE 2011-10-10T00:12:12Z"),
    receive_data(P),

    %% select different folder
    gen_tcp:send(P, "tagp12 SELECT SENT"),
    receive_data(P),

    %% fetch with date cursor
    gen_tcp:send(P, "tagp13 FETCH AFTER DATE 2011-10-10T00:12:12Z"),
    receive_data(P),

    %% fetch with id cursor
    gen_tcp:send(P, "tagp14 FETCH AFTER ID 1"),
    receive_data(P),

    %% fetch with id cursor
    gen_tcp:send(P, "tagp15 FETCH AFTER ID 5"),
    receive_data(P).

client_q() ->
    %% Starting client Q
    {ok, Q} = gen_tcp:connect({127,0,0,1}, 8091, [{active, false}, {packet, 0}]),

    %% Register a number
    gen_tcp:send(Q, "tagq1 REGISTER 1234567890 pwd abhay"),
    receive_data(Q),

    %% Valid Auth
    gen_tcp:send(Q, "tagq2 AUTH 1234567890 pwd"),
    receive_data(Q),

    %% send msg
    gen_tcp:send(Q, "tagq3 SEND 01234789 hello hello :)"),
    receive_data(Q).


%%%===================================================================
%%% Internal functions
%%%===================================================================

receive_data(Socket) ->
    case gen_tcp:recv(Socket, 0, 500) of
	{ok, Data} ->
	    io:format("Server says: ~p~n~n", [Data]),
	    receive_data(Socket);
	_ ->
	    ok
    end.
