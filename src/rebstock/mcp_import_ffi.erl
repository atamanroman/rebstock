-module(mcp_import_ffi).
-export([with_connection/3, valid_date/3]).

with_connection(Uri, Apply, Work) ->
    case sqlight:open(Uri) of
        {error, _} -> {error, <<"Cannot open import database">>};
        {ok, Connection} ->
            try
                {ok, _} = sqlight:exec(<<"PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000">>, Connection),
                Begin = case Apply of true -> <<"BEGIN IMMEDIATE">>; false -> <<"BEGIN">> end,
                case sqlight:exec(Begin, Connection) of
                    {error, _} -> {error, <<"Cannot begin import transaction">>};
                    {ok, _} ->
                        case Work(Connection) of
                            {ok, _} = Success ->
                                Finish = case Apply of true -> <<"COMMIT">>; false -> <<"ROLLBACK">> end,
                                case sqlight:exec(Finish, Connection) of
                                    {ok, _} -> Success;
                                    {error, _} -> {error, <<"Cannot finish import transaction">>}
                                end;
                            {error, _} = Failure -> Failure
                        end
                end
            catch
                _:_ -> {error, <<"Import failed unexpectedly; transaction rolled back">>}
            after
                _ = sqlight:exec(<<"ROLLBACK">>, Connection),
                _ = sqlight:close(Connection)
            end
    end.

valid_date(Year, Month, Day) ->
    calendar:valid_date({Year, Month, Day}).
