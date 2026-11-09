-module(rebstock_mcp_db_ffi).
-export([with_open_connection/2, transaction/2]).

with_open_connection(Connection, Run) ->
    try Run()
    catch _:_ -> {error, <<"Database operation failed">>}
    after sqlight:close(Connection)
    end.

transaction(Connection, Run) ->
    case sqlight:exec(<<"BEGIN IMMEDIATE">>, Connection) of
        {ok, nil} ->
            try Run() of
                {ok, _} = Result ->
                    case sqlight:exec(<<"COMMIT">>, Connection) of
                        {ok, nil} -> Result;
                        _ ->
                            sqlight:exec(<<"ROLLBACK">>, Connection),
                            {error, <<"Database commit failed">>}
                    end;
                {error, _} = Error ->
                    sqlight:exec(<<"ROLLBACK">>, Connection),
                    Error
            catch _:_ ->
                sqlight:exec(<<"ROLLBACK">>, Connection),
                {error, <<"Database transaction failed">>}
            end;
        _ -> {error, <<"Database busy or unavailable">>}
    end.
