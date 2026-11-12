-module(mcp_oauth_ffi).
-behaviour(gen_server).
-export([verify/2, valid_config/1, resource_origin/1, metadata_uri/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-include_lib("public_key/include/public_key.hrl").

-define(MAX_JWKS, 262144).
-define(CACHE, rebstock_mcp_jwks_cache).

verify(Token, Config = {config, Resource, Issuer, Uri, Client, Scope, UsernameClaim}) ->
    try
        true = valid_config(Config),
        true = byte_size(Token) =< 16384,
        [Header64, Claims64, Signature64] = binary:split(Token, <<".">>, [global]),
        Header = json_object(base64url(Header64)),
        Claims = json_object(base64url(Claims64)),
        <<"RS256">> = maps:get(<<"alg">>, Header),
        <<"at+jwt">> = maps:get(<<"typ">>, Header),
        false = maps:is_key(<<"crit">>, Header),
        Kid = maps:get(<<"kid">>, Header),
        true = safe_string(Kid, 256),
        Issuer = maps:get(<<"iss">>, Claims),
        true = audience_matches(maps:get(<<"aud">>, Claims), Resource),
        Client = maps:get(<<"client_id">>, Claims),
        Now = erlang:system_time(second),
        Expires = maps:get(<<"exp">>, Claims),
        true = is_integer(Expires) andalso Expires > Now,
        true = valid_not_before(maps:get(<<"nbf">>, Claims, absent), Now),
        Username = maps:get(UsernameClaim, Claims),
        true = username(Username),
        TokenScopes = token_scopes(Claims),
        Signature = base64url(Signature64),
        Content = <<Header64/binary, ".", Claims64/binary>>,
        case signing_key(Uri, Kid) of
            {ok, Key} ->
                case public_key:verify(Content, sha256, Signature, Key) of
                    true ->
                        case lists:member(Scope, TokenScopes) of
                            true -> {ok, Username};
                            false -> {error, forbidden}
                        end;
                    false -> {error, unauthorized}
                end;
            {error, Failure} -> {error, Failure}
        end
    catch
        _:_ -> {error, unauthorized}
    end.

%% Authelia emits scp arrays; other issuers use the OAuth scope string.
%% If both are present, require agreement rather than merging permissions.
token_scopes(Claims) ->
    case {maps:find(<<"scope">>, Claims), maps:find(<<"scp">>, Claims)} of
        {{ok, Scope}, error} when is_binary(Scope) ->
            binary:split(Scope, <<" ">>, [global]);
        {error, {ok, Scopes}} -> scope_array(Scopes);
        {{ok, Scope}, {ok, Scopes}} when is_binary(Scope) ->
            Parsed = binary:split(Scope, <<" ">>, [global]),
            true = lists:usort(Parsed) =:= lists:usort(scope_array(Scopes)),
            Parsed;
        _ -> erlang:error(invalid_scope)
    end.

scope_array(Scopes) when is_list(Scopes) ->
    true = lists:all(fun(S) -> is_binary(S) andalso byte_size(S) > 0 end, Scopes),
    Scopes;
scope_array(_) -> erlang:error(invalid_scope).

audience_matches(Audience, Resource) when is_binary(Audience) -> Audience =:= Resource;
audience_matches(Audience, Resource) when is_list(Audience) ->
    lists:all(fun is_binary/1, Audience) andalso lists:member(Resource, Audience);
audience_matches(_, _) -> false.

valid_not_before(absent, _) -> true;
valid_not_before(Value, Now) -> is_integer(Value) andalso Value =< Now.

username(Value) when is_binary(Value), byte_size(Value) > 0, byte_size(Value) =< 256 ->
    case unicode:characters_to_list(Value) of
        Chars when is_list(Chars) ->
            string:trim(Chars) =:= Chars andalso
            lists:all(fun(C) -> C > 32 andalso C =/= 127 end, Chars);
        _ -> false
    end;
username(_) -> false.

valid_config({config, Resource, Issuer, JwksUri, Client, Scope, UsernameClaim}) ->
    safe_url(Resource) andalso safe_url(Issuer) andalso safe_url(JwksUri) andalso
    safe_string(Client, 256) andalso safe_string(Scope, 128) andalso
    safe_string(UsernameClaim, 128);
valid_config(_) -> false.

safe_url(Value) when is_binary(Value), byte_size(Value) =< 2048 ->
    try
        #{scheme := Scheme, host := Host} = Parsed = uri_string:parse(Value),
        true = safe_string(Value, 2048),
        true = byte_size(Host) > 0,
        false = maps:is_key(userinfo, Parsed),
        false = maps:is_key(fragment, Parsed),
        false = maps:is_key(query, Parsed),
        true = valid_port(maps:get(port, Parsed, 443)),
        Scheme =:= <<"https">> orelse
        (Scheme =:= <<"http">> andalso lists:member(Host, [<<"127.0.0.1">>, <<"::1">>]))
    catch _:_ -> false end;
safe_url(_) -> false.

valid_port(Port) -> is_integer(Port) andalso Port > 0 andalso Port =< 65535.

safe_string(Value, Limit) when is_binary(Value), byte_size(Value) > 0, byte_size(Value) =< Limit ->
    lists:all(fun(C) -> C >= 33 andalso C =< 126 andalso C =/= $" andalso C =/= $\\ end,
              binary_to_list(Value));
safe_string(_, _) -> false.

resource_origin(Resource) ->
    try
        #{scheme := Scheme, host := Host} = Parsed = uri_string:parse(Resource),
        Authority = (maps:with([scheme, host, port], Parsed))#{path => <<>>},
        Normalized = case maps:get(port, Authority, absent) of
            443 when Scheme =:= <<"https">> -> maps:remove(port, Authority);
            80 when Scheme =:= <<"http">> -> maps:remove(port, Authority);
            _ -> Authority
        end,
        true = byte_size(Host) > 0,
        uri_string:recompose(Normalized)
    catch _:_ -> <<>> end.

metadata_uri(Resource) ->
    Parsed = uri_string:parse(Resource),
    Path = maps:get(path, Parsed, <<>>),
    <<(resource_origin(Resource))/binary, "/.well-known/oauth-protected-resource", Path/binary>>.

base64url(Value) when byte_size(Value) > 0 ->
    true = lists:all(fun(C) ->
        (C >= $A andalso C =< $Z) orelse (C >= $a andalso C =< $z) orelse
        (C >= $0 andalso C =< $9) orelse C =:= $- orelse C =:= $_
    end, binary_to_list(Value)),
    base64:decode(Value, #{mode => urlsafe, padding => false}).

json_object(Value) ->
    Push = fun(Key, Item, Acc) ->
        false = lists:keymember(Key, 1, Acc),
        [{Key, Item} | Acc]
    end,
    {Object, ok, Rest} = json:decode(Value, ok, #{object_push => Push}),
    true = is_map(Object),
    <<>> = string:trim(Rest),
    Object.

signing_key(Uri, Kid) ->
    try
        case gen_server:start({local, ?CACHE}, ?MODULE, [], []) of
            {ok, _} -> ok;
            {error, {already_started, _}} -> ok
        end,
        gen_server:call(?CACHE, {key, Uri, Kid}, 3000)
    catch _:_ -> {error, unavailable} end.

init([]) -> {ok, []}.

handle_call({key, Uri, Kid}, _From, Cache) ->
    Now = erlang:monotonic_time(second),
    case lists:keytake(Uri, 1, Cache) of
        {value, Entry = {Uri, Keys, Expires, RetryAfter, Failure}, Rest} when Now < Expires ->
            case maps:find(Kid, Keys) of
                {ok, Key} -> {reply, {ok, Key}, [Entry | Rest]};
                error when Now < RetryAfter -> {reply, {error, Failure}, Cache};
                error -> fetch_key(Uri, Kid, Now, Now + 5, Rest, Entry)
            end;
        {value, _, Rest} -> fetch_key(Uri, Kid, Now, Now, Rest, absent);
        false -> fetch_key(Uri, Kid, Now, Now, Cache, absent)
    end;
handle_call(_, _, Cache) -> {reply, {error, unavailable}, Cache}.

handle_cast(_, Cache) -> {noreply, Cache}.
handle_info(_, Cache) -> {noreply, Cache}.

fetch_key(Uri, Kid, Now, RetryAfter, Cache, Previous) ->
    {Reply, Entry} = case fetch_keys(Uri) of
        {ok, Keys} ->
            Result = case maps:find(Kid, Keys) of
                {ok, Key} -> {ok, Key};
                error -> {error, unauthorized}
            end,
            NextRetry = case Result of
                {error, unauthorized} -> Now + 5;
                _ -> RetryAfter
            end,
            {Result, {Uri, Keys, Now + 300, NextRetry, unauthorized}};
        error ->
            Failed = case Previous of
                {Uri, Keys, Expires, _, _} -> {Uri, Keys, Expires, Now + 5, unavailable};
                absent -> {Uri, #{}, Now + 5, Now + 5, unavailable}
            end,
            {{error, unavailable}, Failed}
    end,
    {reply, Reply, lists:sublist([Entry | Cache], 8)}.

fetch_keys(Uri) ->
    try
        {ok, _} = application:ensure_all_started(inets),
        {ok, _} = application:ensure_all_started(ssl),
        HttpOptions = [{timeout, 2000}, {connect_timeout, 1500}, {autoredirect, false} | tls_options(Uri)],
        Options = [{sync, false}, {stream, {self, once}}, {body_format, binary} | response_limits()],
        {ok, RequestId} = httpc:request(get, {binary_to_list(Uri), [{"accept", "application/json"}]}, HttpOptions, Options),
        Deadline = erlang:monotonic_time(millisecond) + 2000,
        Body = try receive_jwks(RequestId, Deadline, undefined, [], 0)
               after httpc:cancel_request(RequestId) end,
        #{<<"keys">> := Keys} = json_object(Body),
        true = is_list(Keys) andalso length(Keys) > 0 andalso length(Keys) =< 64,
        SigningKeys = lists:filtermap(fun signing_jwk/1, Keys),
        true = length(SigningKeys) > 0,
        KeyMap = maps:from_list(SigningKeys),
        true = map_size(KeyMap) =:= length(SigningKeys),
        {ok, KeyMap}
    catch _:_ -> error end.

-if(?OTP_RELEASE >= 29).
response_limits() -> [{max_header_size, 16384}, {max_body_size, ?MAX_JWKS}].
-else.
response_limits() -> [].
-endif.

tls_options(<<"http://", _/binary>>) -> [];
tls_options(_) ->
    [{ssl, [{verify, verify_peer}, {cacerts, public_key:cacerts_get()},
            {customize_hostname_check, [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}]}].

receive_jwks(RequestId, Deadline, Stream, Chunks, Size) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {http, {RequestId, stream_start, Headers, Handler}} ->
            case proplists:get_value("content-length", Headers) of
                undefined -> ok;
                Length -> true = list_to_integer(Length) =< ?MAX_JWKS
            end,
            httpc:stream_next(Handler),
            receive_jwks(RequestId, Deadline, Handler, Chunks, Size);
        {http, {RequestId, stream, Chunk}} when Size + byte_size(Chunk) =< ?MAX_JWKS ->
            httpc:stream_next(Stream),
            receive_jwks(RequestId, Deadline, Stream, [Chunk | Chunks], Size + byte_size(Chunk));
        {http, {RequestId, stream_end, _}} -> iolist_to_binary(lists:reverse(Chunks));
        {http, {RequestId, {{_, 200, _}, _, Body}}} when byte_size(Body) =< ?MAX_JWKS -> Body;
        {http, {RequestId, _}} ->
            httpc:cancel_request(RequestId),
            error(jwks_unavailable);
        {http, {RequestId, stream, _}} ->
            httpc:cancel_request(RequestId),
            error(jwks_too_large)
    after Remaining ->
        httpc:cancel_request(RequestId),
        error(jwks_timeout)
    end.

signing_jwk(Jwk) when is_map(Jwk) ->
    case {maps:get(<<"kty">>, Jwk, absent), maps:get(<<"use">>, Jwk, <<"sig">>),
          maps:get(<<"alg">>, Jwk, <<"RS256">>), maps:get(<<"key_ops">>, Jwk, [<<"verify">>])} of
        {<<"RSA">>, <<"sig">>, <<"RS256">>, Ops} when is_list(Ops) ->
            case lists:member(<<"verify">>, Ops) of
                true ->
                    Kid = maps:get(<<"kid">>, Jwk),
                    true = safe_string(Kid, 256),
                    N = base64url(maps:get(<<"n">>, Jwk)),
                    E = base64url(maps:get(<<"e">>, Jwk)),
                    true = byte_size(N) >= 256 andalso byte_size(N) =< 1024,
                    true = byte_size(E) > 0 andalso byte_size(E) =< 8,
                    Modulus = binary:decode_unsigned(N),
                    Exponent = binary:decode_unsigned(E),
                    true = Modulus >= (1 bsl 2047) andalso Modulus rem 2 =:= 1,
                    true = Exponent >= 3 andalso Exponent rem 2 =:= 1,
                    {true, {Kid, #'RSAPublicKey'{modulus = Modulus, publicExponent = Exponent}}};
                false -> false
            end;
        _ -> false
    end;
signing_jwk(_) -> false.
