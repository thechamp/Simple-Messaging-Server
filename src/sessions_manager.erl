%%%-------------------------------------------------------------------
%%% @author  Abhay Jain <abhay_1303@yahoo.co.in>
%%% @doc  This is a helper module for TCP/IP server. This contains all
%%%       methods to process command, store & retrieve data from mnesia
%%% @end
%%% Created : 10 Nov 2012 by  Abhay Jain
%%%-------------------------------------------------------------------
-module(sessions_manager).

%% API
-export([
	 start/0,
	 start_new_session/1,
	 send_reply/3,
	 register_new_user/2,
	 try_user_auth/2,
	 select_folder/2,
	 fetch_messages/2,
	 send_message/2,
	 quit_session/2
	]).

%% Stores the list of currently active sessions
-record(session, {port, user, mode}).

%% Stores the registered users with server
-record(user, {number, name, password}).

%% A record to auto increment message ids, used in next table
-record(message_id, {type, id}).

%% Details of messages sent from clients
-record(message, {id, from, to, time, data}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc This method starts mnesia, creates table and indexes
%% @spec start() -> ok
%% @end
%%--------------------------------------------------------------------
start() ->
    %% Start Mnesia and create tables in RAM when module starts
    mnesia:start(),
    mnesia:create_table(session, [{ram_copies, [node()]},
				  {attributes,
				   record_info(fields,session)}]),
    mnesia:add_table_index(session, port),
    
    mnesia:create_table(user, [{ram_copies, [node()]},
			       {attributes,
				record_info(fields,user)}]),
    mnesia:add_table_index(user, number),
    mnesia:create_table(message_id, [{ram_copies, [node()]},
				     {attributes,
				      record_info(fields,message_id)}]),
    mnesia:create_table(message, [{ram_copies, [node()]},
				  {attributes,
				   record_info(fields,message)}]),
    mnesia:add_table_index(message, id),
    ok.

%%--------------------------------------------------------------------
%% @doc This method adds socket to session table when client connects
%%      to TCP server.
%% @spec start_new_session(Socket::socket()) -> ok
%% @end
%%--------------------------------------------------------------------
start_new_session(Socket) ->
    T = fun() ->
		mnesia:dirty_write(#session{port=Socket})
	end,
    mnesia:transaction(T),
    ok.

%%--------------------------------------------------------------------
%% @doc This method is used to send message to client on its socket
%% @spec send_reply(Socket::socket(), Tag::string(), Reason::string() ->
%%       ok | {error, Reason}
%%       Reason = term()
%% @end
%%--------------------------------------------------------------------
send_reply(Socket, Tag, Reason) ->
    Reply = string:join([Tag, Reason], " "),
    io:format("Sending ~p to socket ~p~n", [Reply, Socket]),
    gen_tcp:send(Socket, Reply).

%%--------------------------------------------------------------------
%% @doc This method registers a new number by entering its information
%%      in mnesia table.
%% @spec register_new_user(Socket::socket(), Tokens::list()) ->
%%       ok | {error, Reason}
%%       Reason = term()
%% @end
%%--------------------------------------------------------------------
register_new_user(Socket, Tokens) ->
    Tag = lists:nth(1, Tokens),
    if length(Tokens) < 5 ->
	    %% There should be atleast 5 arguments for this command
	    %% Tag REGISTER Number Password Name
	    send_reply(Socket, Tag, "BAD");
       
       true ->
	    Number = lists:nth(3, Tokens),
	    case string:len(Number) of
		10 ->
		    %% Proceed only when there are 10 digits in Number
		    %% Retrieve all information from command and store in database
		    Password = lists:nth(4, Tokens),
		    Name = string:join(lists:nthtail(4, Tokens), " "),
		    
		    case if_already_exists(Number) of
			false ->
			    Pattern = #user{number=Number,
					    name=Name,
					    password=Password},
			    case mnesia:transaction(fun() ->
							    mnesia:dirty_write(Pattern)
						    end) of
				{atomic, ok} ->
				    %% User was successfully registered
				    io:format("~p was successfully registered~n", [Number]),
				    send_reply(Socket, Tag, "OK");
				_->
				    %% Other issue on inserting
				    send_reply(Socket, Tag, "BAD")
			    end;
			_ ->
			    %% This number already exists in database
			    io:format("~p is already registered", [Number]),
			    send_reply(Socket, Tag, "NO")
		    end;
		_ ->
		    %% Length of number is not 10
		    send_reply(Socket, Tag, "BAD")
	    end
    end.

%%--------------------------------------------------------------------
%% @doc This method authenticates the user
%% @spec try_user_auth(Socket::socket(), Tokens::list()) -> ok | {error, Reason}
%%       Reason = term()
%% @end
%%--------------------------------------------------------------------
try_user_auth(Socket, Tokens) ->    
    Tag = lists:nth(1, Tokens),    
    if length(Tokens) < 4 ->
	    %% There should be atleast 4 arguments for this command
	    %% Tag AUTH Number Password
	    send_reply(Socket, Tag, "BAD");
       true ->
	    %% Retrieve all information from command and check for auth
	    Number = lists:nth(3, Tokens),
	    Password = lists:nth(4, Tokens),
	    Pattern = #user{number=Number,
			    password=Password,
			    _='_'},
	    case mnesia:transaction(fun() ->
					    mnesia:dirty_match_object(Pattern)
				    end) of
		{atomic, Result} when is_list(Result),
			    length(Result) == 1 ->
		    %% User was successfully authenticated,
		    %% Connect this socket with this user
		    connect_socket_with_user(Socket, Number),
		    io:format("~p was successfully authenticated on socket ~p~n", [Number, Socket]),
		    send_reply(Socket, Tag, "OK");
		_ ->
		    %% No such combination of user-password exists
		    io:format("Invalid auth info for ~p~n", [Number]),
		    send_reply(Socket, Tag, "NO")
	    end
    end.

%%--------------------------------------------------------------------
%% @doc This method selects the folder for client
%% @spec select_folder(Socket::socket(), Tokens::list()) -> ok | {error, Reason}
%%       Reason = term()
%% @end
%%--------------------------------------------------------------------
select_folder(Socket, Tokens) ->
    Tag = lists:nth(1, Tokens),
    User = user_authenticated_for_socket(Socket),
    if User == false ->
	    %% No user is authenticated on this socket
	    %% So client can not select folder
	    send_reply(Socket, Tag, "NO");
       true ->
	    if length(Tokens) < 3 ->
		    %% There should be atleast 3 arguments for this command
		    %% Tag SELECT Folder
		    send_reply(Socket, Tag, "BAD");
	       true ->
		    Folder = lists:nth(3, Tokens),
		    if Folder =/= "INBOX" andalso Folder =/= "SENT" ->
			    %% Invalid folder name
			    send_reply(Socket, Tag, "NO");
		       true ->
			    %% Set the mode of this user as the name of folder
			    %% Whenever user wants to fetch messages, use mode
			    %% to identify the folder name
			    Pattern = User#session{mode=Folder},
			    mnesia:transaction(fun() ->
						       mnesia:dirty_write(Pattern)
					       end),
			    send_reply(Socket, Tag, "OK")
		    end
	    end
    end.

%%--------------------------------------------------------------------
%% @doc This method is called when user wants to fetch list of messages
%%      based on cursor and folder, it calls function that generates
%%      actual message list.
%% @spec fetch_messages(Socket::socket(), Tokens::list()) -> ok | {error, Reason}
%%       Reason = term()
%% @end
%%--------------------------------------------------------------------
fetch_messages(Socket, Tokens) ->
    Tag = lists:nth(1, Tokens),
    User = user_authenticated_for_socket(Socket),
    if User == false ->
	    %% No user is authenticated on this socket
	    %% So client cant fetch messages
	    send_reply(Socket, Tag, "BAD");
       true ->
	    if length(Tokens) < 2 ->
		    %% There should be atleast 2 arguments for this command
		    %% Tag FETCH
		    send_reply(Socket, Tag, "BAD");
	       true ->
		    Number = User#session.user,
		    Cursor = lists:nthtail(2, Tokens),
		    if
			%% User has selected INBOX folder
			User#session.mode == "INBOX" ->
			    fetch_and_send_user_messages(Tag, Socket, inbox, Number, Cursor);
			%% User has selected SENT folder
			User#session.mode == "SENT" ->
			    fetch_and_send_user_messages(Tag, Socket, sent, Number, Cursor);
			%% User has not selected any folder yet
			%% Messages can not be fetched
			true ->
			    send_reply(Socket, Tag, "ERROR")
		    end
	    end
    end.

%%--------------------------------------------------------------------
%% @doc This method is called when a client sends message to other client
%% @spec send_message(Socket::socket(), Tokens::list()) -> ok | {error, Reason}
%%       Reason = term()
%% @end
%%--------------------------------------------------------------------
send_message(Socket, Tokens) ->
    Tag = lists:nth(1, Tokens),
    User = user_authenticated_for_socket(Socket),    
    if User == false ->
	    %% This socket has no authenticated user
	    %% So client cant send any message
	    send_reply(Socket, Tag, "BAD");
       true ->
	    if length(Tokens) < 4 ->
		    %% There should be atlease 4 arguments for this command
		    %% Tag SEND Number Message
		    send_reply(Socket, Tag, "BAD");
	       true ->
		    %% Find info of this message and insert in database
		    Sender = User#session.user,
		    Recvr = lists:nth(3, Tokens),
		    Message = string:join(lists:nthtail(3, Tokens), " "),
		    MessageId = generate_message_id(),
		    Pattern = #message{id=MessageId,
				       from=Sender,
				       to=Recvr,
				       time=calendar:datetime_to_gregorian_seconds(calendar:universal_time()),
				       data=Message},
		    mnesia:transaction(fun() ->
					       mnesia:dirty_write(Pattern)
				       end),
		    send_reply(Socket, Tag, "OK")
	    end
    end.

%%--------------------------------------------------------------------
%% @doc  When a client wants to terminate session
%% @spec quit_session(Socket::socket(), Tokens::list()) -> ok | {error, Reason}
%%       Reason = term()
%% @end
%%--------------------------------------------------------------------
quit_session(Socket, Tokens) ->
    Tag = lists:nth(1, Tokens),
    Pattern = #session{port=Socket},
    %% Delete this socket from database
    mnesia:transaction(fun() ->
			       mnesia:dirty_delete_object(Pattern)
		       end),
    send_reply(Socket, Tag, "OK").


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc  Before registering a number, this method checks if it already
%%       exists in our database.
%% @spec if_already_exists(Number::string()) -> true | false
%% @end
%%--------------------------------------------------------------------
if_already_exists(Number) ->
    Pattern = #user{number=Number, _='_'},
    case mnesia:transaction(fun() ->
				    mnesia:dirty_match_object(Pattern)
			    end) of
	{atomic, []} ->
	    false;
	_ ->
	    true
    end.

%%--------------------------------------------------------------------
%% @doc  This method maps Number to Socket in session database and puts
%%       this client online, after user authenticates his number.
%% @spec connect_socket_with_user(Socket::socket(), Number::string()) ->
%%       ok
%% @end
%%--------------------------------------------------------------------
connect_socket_with_user(Socket, Number) ->
    Pattern = #session{port=Socket, _='_'},
    case mnesia:transaction(fun() ->
				    mnesia:dirty_match_object(Pattern)
			    end) of
	{atomic, Result} when is_list(Result),
		    length(Result) == 1 ->
	    [Record] = Result,
	    Pattern2 = Record#session{user=Number, mode=online},
	    mnesia:transaction(fun() ->
				       mnesia:dirty_write(Pattern2)
			       end);
	_ ->
	    ok
    end,
    ok.

%%--------------------------------------------------------------------
%% @doc  This method returns information about the user who is connected
%%       to the given socket in session database. If there is no user
%%       authenticated with socket yet, it returns false.
%% @spec  user_authenticated_for_socket(Socket::socket()) -> false |
%%        Record
%%        Record = #session()
%% @end
%%--------------------------------------------------------------------
user_authenticated_for_socket(Socket) ->
    Pattern = #session{port=Socket, _='_'},
    case mnesia:transaction(fun() ->
				    mnesia:dirty_match_object(Pattern)
			    end) of
	{atomic, Result} when is_list(Result),
		    length(Result) == 1 ->
	    [Record] = Result,
	    if Record#session.user == false ->
		    false;
	       true ->
		    Record
	    end;
	_ ->
	    false
    end.

%%--------------------------------------------------------------------
%% @doc  This method generates the next message id to be stored
%% @spec generate_message_id() -> Id
%%       Id = integer()
%% @end
%%--------------------------------------------------------------------
generate_message_id() ->
    mnesia:dirty_update_counter(message_id, messages, 1).

%%--------------------------------------------------------------------
%% @doc  this method fetches the list of messages for a client from
%%       specified folder based on cursor defined and sends them.
%% @spec fetch_and_send_user_messages(Tag::string(), Socket::socket(),
%%         Type::atom(), Number::string(), Cursor::list()) -> ok
%% @end
%%--------------------------------------------------------------------
fetch_and_send_user_messages(Tag, Socket, Type, Number, Cursor) ->
    if
	%% Client wants to fetch all messages without cursor
	length(Cursor) == 0 ->
	    if Type == inbox ->
		    %% Retrieve INBOX messages
		    Pattern = #message{to=Number, _='_'};
	       true ->
		    %% Retrieve SENT messages
		    Pattern = #message{from=Number, _='_'}
	    end,
	    case mnesia:transaction(fun() ->
					    mnesia:dirty_match_object(Pattern)
				    end) of
		{atomic, Result} ->
		    Records = Result;
		_->
		    Records = []
	    end;
	true ->
	    CursorType = lists:nth(2, Cursor),
	    if CursorType == "ID" ->
		    %% Client wants to fetch messages with ID cursor
		    Id = list_to_integer(lists:nth(3, Cursor)),
		    if Type == inbox ->
			    MatchHead = #message{to=Number, id='$1', _='_'};
		       true ->
			    MatchHead = #message{from=Number, id='$1', _='_'}
		    end,
		    Guard = {'>', '$1', Id},
		    Result = ['$_'],
		    MatchSpecs = [{MatchHead, [Guard], Result}];
	       
	       CursorType == "DATE" ->
		    %% Client wants to fetch messages with DATE cursor
		    Date = calendar:datetime_to_gregorian_seconds(convert_date_to_erlang_format(lists:nth(3, Cursor))),
		    if Type == inbox ->
			    MatchHead = #message{to=Number, time='$1', _='_'};
		       true ->
			    MatchHead = #message{from=Number, time='$1', _='_'}
		    end,
		    Guard = {'>', '$1', Date},
		    Result = ['$_'],
		    MatchSpecs = [{MatchHead, [Guard], Result}];
	       true ->
		    %% Bad cursor
		    MatchSpecs = []
	    end,
	    
	    if MatchSpecs == [] ->
		    Records = [];
	       true ->
		    case mnesia:transaction(fun() ->
						    mnesia:select(message, MatchSpecs)
					    end) of
			{atomic, Results} ->
			    Records = Results;
			_->
			    Records = []
		    end
	    end
    end,
    
    Reply = string:join(["OK", integer_to_list(length(Records))], " "),
    send_reply(Socket, Tag, Reply),
    lists:foreach(fun(Record) ->
			  Msg = prepare_message(Record#message.id, Record#message.from,
						Record#message.to, Record#message.time,
						Record#message.data),
			  send_reply(Socket, "*", Msg)
		  end, Records).

%%--------------------------------------------------------------------
%% @doc  This function converts the given date format Y-M-DTH:M:SZ
%%       to erlang datetime format {{Y,M,D}, {H,M,S}}
%% @spec  convert_date_to_erlang_format(ClientDateTime::string()) ->
%%        ErlangDateTime
%%        ErlangDateTime = datetime()
%% @end
%%--------------------------------------------------------------------
convert_date_to_erlang_format(ClientDateTime) ->
    Tokens = string:tokens(ClientDateTime, ":-TZ"),
    ErlangDate = {list_to_integer(lists:nth(1, Tokens)),
		  list_to_integer(lists:nth(2, Tokens)),
		  list_to_integer(lists:nth(3, Tokens))},
    ErlangTime = {list_to_integer(lists:nth(4, Tokens)),
		  list_to_integer(lists:nth(5, Tokens)),
		  list_to_integer(lists:nth(6, Tokens))},
    {ErlangDate, ErlangTime}.


%%--------------------------------------------------------------------
%% @doc  This method converts the erlang datetime {{Y,M,D}, {H,M,S}} to
%%       client datetime format Y-M-DTH:M:SZ
%% @spec  convert_date_from_erlang_format(ErlangDateTime::datetime()) ->
%%        ClientDateTime
%%        ClientDateTime = string()
%% @end
%%--------------------------------------------------------------------
convert_date_from_erlang_format(ErlangDateTime) ->
    {ErlangDate, ErlangTime} = ErlangDateTime,
    ClientDate = string:join([integer_to_list(element(1, ErlangDate)),
			      integer_to_list(element(2, ErlangDate)),
			      integer_to_list(element(3, ErlangDate))], "-"),
    ClientTime = string:join([integer_to_list(element(1, ErlangTime)),
			      integer_to_list(element(2, ErlangTime)),
			      integer_to_list(element(3, ErlangTime))], ":"),
    ClientDate ++ "T" ++ ClientTime ++ "Z".

			     
%%--------------------------------------------------------------------
%% @doc  This method prepares the messages in the specified format
%%       ID: id\r\nFrom:from\r\nTo:to\r\nDate:date\r\nMessage:message
%% @spec  prepare_message(ID::integer(), From::string(), To::string(),
%%        Time::seconds(), Msg::string()) -> Message
%%        Message = string()
%% @end
%%--------------------------------------------------------------------
prepare_message(ID, From, To, Time, Msg) ->
    ID1 = "ID: " ++ integer_to_list(ID),
    From1 = "From:" ++ From,
    To1 = "To:" ++ To,
    Time1 = "Date:" ++ convert_date_from_erlang_format(calendar:gregorian_seconds_to_datetime(Time)),
    Msg1 = "Message:" ++ Msg,
    string:join([ID1, From1, To1, Time1, Msg1], "\r\n").
