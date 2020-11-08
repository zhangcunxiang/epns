-module(epns_apns).

%%% ==================================================================
%%% Macro
%%% ==================================================================

-define(COMMAND_REQ, 1).
-define(COMMAND_RESP, 8).
-define(EXPIRY, (os:system_time(second) + 604800)).
-define(TOKEN_LENGTH, 32).
-define(TIMEOUT, 50000).

%%% ==================================================================
%%% API
%%% ==================================================================

-export([push/1, recv/2]).

%% -------------------------------------------------------------------
%% @doc
%% Send APNS push notification
%% @end
%% -------------------------------------------------------------------
-spec push(Data :: maps:map()) -> Result :: tuple().

push(#{playload := P, key := K, cert := C, url := U, token := T}) ->
  case ssl:connect(U, 2195, [{certfile, C}, {keyfile, K}, {mode, binary}, {verify, verify_none}], ?TIMEOUT) of
    {ok, Socket} ->
      ID = rand:uniform(9999),
      Payload = jiffy:encode(P),
      PayloadLen = erlang:byte_size(Payload),
      DeviceToken = binary_to_integer(T, 16),
      Packet = <<?COMMAND_REQ:8, ID:32/big, ?EXPIRY:4/big-unsigned-integer-unit:8,
        ?TOKEN_LENGTH:16/big, DeviceToken:256/integer, PayloadLen:16/big, Payload/binary>>,
      ssl:send(Socket, Packet),
      ssl:close(Socket, 0),
      {ok, apns};
    {error, Reason} ->
      {error, Reason}
  end.

%% -------------------------------------------------------------------
%% @doc
%% Receive errors of APNS
%% Use inside of push/1: ssl:controlling_process(Socket, spawn(fun() -> recv(self(), 100) end))
%% @end
%% -------------------------------------------------------------------
-spec recv(Pid :: pid(), Timeout :: integer()) -> Result :: term().

recv(Pid, Timeout) ->
  receive
    {ssl, Sock, <<?COMMAND_RESP:8, Status, UserID:32/big>>} ->
      lager:error("APNS Error: [~p:~p/1]: Reason: ~p, message ID: ~p~n", [?MODULE, push, convert_status(Status), UserID]),
      ssl:close(Sock),
      Pid ! {error, UserID};
    {ssl_closed, _} -> ok
  after Timeout -> exit(Pid, normal)
  end.

%% -------------------------------------------------------------------
%% @private
%% @doc
%% Handler for status code of response from APNS
%% @end
%% -------------------------------------------------------------------
-spec convert_status(StatusCode :: integer()) -> Result :: binary().

convert_status(0) -> <<"no errors">>;
convert_status(1) -> <<"processing error">>;
convert_status(2) -> <<"missing device token">>;
convert_status(3) -> <<"missing topic">>;
convert_status(4) -> <<"missing payload">>;
convert_status(5) -> <<"invalid token size">>;
convert_status(6) -> <<"invalid topic size">>;
convert_status(7) -> <<"invalid payload size">>;
convert_status(8) -> <<"invalid token">>;
convert_status(10) -> <<"shutdown">>;
convert_status(128) -> <<"protocol error">>;
convert_status(255) -> <<"unknown">>.
