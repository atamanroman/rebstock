-module(mcp_oauth_test_ffi).
-export([start/0, stop/1, token/3, rotate/1, response/3, delay/2, chunked/1, requests/1]).
-include_lib("public_key/include/public_key.hrl").

start() ->
    Key = public_key:generate_key({rsa, 2048, 65537}),
    {ok, Listen} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true}, {ip, {127,0,0,1}}]),
    {ok, {_, Port}} = inet:sockname(Listen),
    Server = spawn(fun() -> loop(Listen, Key, <<"first">>, default, 0) end),
    {<<"http://127.0.0.1:", (integer_to_binary(Port))/binary, "/jwks">>, Server}.

stop(Server) -> Server ! stop, nil.
rotate(Server) -> call(Server, rotate).
response(Server, Status, Body) -> call(Server, {response, Status, Body}).
delay(Server, Milliseconds) -> call(Server, {delay, Milliseconds}).
chunked(Server) -> call(Server, chunked).
requests(Server) -> call(Server, requests).
token(Server, Header, Claims) -> call(Server, {token, Header, Claims}).

call(Server, Message) ->
    Ref = make_ref(),
    Server ! {self(), Ref, Message},
    receive {Ref, Result} -> Result after 5000 -> error(fixture_timeout) end.

loop(Listen, Key, Kid, Response, Requests) ->
    receive
        stop -> gen_tcp:close(Listen);
        {From, Ref, rotate} ->
            NewKey = public_key:generate_key({rsa, 2048, 65537}),
            From ! {Ref, nil},
            loop(Listen, NewKey, <<"second">>, default, Requests);
        {From, Ref, requests} ->
            From ! {Ref, Requests}, loop(Listen, Key, Kid, Response, Requests);
        {From, Ref, {response, Status, Body}} ->
            From ! {Ref, nil}, loop(Listen, Key, Kid, {Status, Body}, Requests);
        {From, Ref, chunked} ->
            From ! {Ref, nil}, loop(Listen, Key, Kid, chunked, Requests);
        {From, Ref, {delay, Milliseconds}} ->
            From ! {Ref, nil}, loop(Listen, Key, Kid, {delay, Milliseconds}, Requests);
        {From, Ref, {token, Header, Claims}} ->
            Content = <<(base64url(Header))/binary, ".", (base64url(Claims))/binary>>,
            Signature = public_key:sign(Content, sha256, Key),
            From ! {Ref, <<Content/binary, ".", (base64url(Signature))/binary>>},
            loop(Listen, Key, Kid, Response, Requests)
    after 0 ->
        case gen_tcp:accept(Listen, 20) of
            {ok, Socket} ->
                {ok, _} = gen_tcp:recv(Socket, 0, 2000),
                Response1 = case Response of
                    {delay, Milliseconds} -> receive after Milliseconds -> default end;
                    _ -> Response
                end,
                {Status, Body} = case Response1 of
                    chunked -> {200, iolist_to_binary(json:encode(#{<<"keys">> => [jwk(Key, Kid)]}))};
                    default -> {200, iolist_to_binary(json:encode(#{<<"keys">> => [jwk(Key, Kid)]}))};
                    Configured -> Configured
                end,
                Wire = case Response1 of
                    chunked -> ["HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n", integer_to_binary(byte_size(Body), 16), "\r\n", Body, "\r\n0\r\n\r\n"];
                    _ -> ["HTTP/1.1 ", integer_to_list(Status), " Response\r\nContent-Type: application/json\r\nContent-Length: ", integer_to_list(byte_size(Body)), "\r\nConnection: close\r\n\r\n", Body]
                end,
                gen_tcp:send(Socket, Wire),
                gen_tcp:close(Socket),
                loop(Listen, Key, Kid, Response, Requests + 1);
            {error, timeout} -> loop(Listen, Key, Kid, Response, Requests);
            {error, closed} -> ok
        end
    end.

jwk(#'RSAPrivateKey'{modulus = N, publicExponent = E}, Kid) ->
    #{<<"kty">> => <<"RSA">>, <<"kid">> => Kid, <<"use">> => <<"sig">>, <<"alg">> => <<"RS256">>,
      <<"n">> => base64url(binary:encode_unsigned(N)), <<"e">> => base64url(binary:encode_unsigned(E))}.

base64url(Value) -> base64:encode(Value, #{mode => urlsafe, padding => false}).
