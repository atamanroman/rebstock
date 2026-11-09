-module(coverage_ffi).
-export([run_with_coverage/0]).

modules() ->
    [rebstock, rebstock@auth, rebstock@config, rebstock@db,
     rebstock@router, rebstock@seed, rebstock@ulid, rebstock@vivino,
     rebstock@web@cellar, rebstock@web@components, rebstock@web@home,
     rebstock@web@lists, rebstock@web@ratings,
     rebstock@web@shared, rebstock@web@wineries, rebstock@web@wines,
     rebstock@web@wishlist].

run_with_coverage() ->
    %% Start cover and instrument modules
    cover:start(),
    lists:foreach(fun(M) ->
        case cover:compile_beam(M) of
            {ok, _} -> ok;
            {error, _} -> ok
        end
    end, modules()),

    %% Run gleeunit (which calls erlang:halt), but trap the halt
    %% by overriding halt via a process that prints coverage first
    Self = self(),
    spawn(fun() ->
        %% Override halt to send message instead
        erlang:process_flag(trap_exit, true),
        Self ! ready,
        receive
            {halt, Code} ->
                report(),
                erlang:halt(Code)
        end
    end),
    receive ready -> ok end,

    %% Patch erlang:halt by using an on_halt callback
    %% Actually, we can't easily intercept halt. Instead, run eunit directly.
    TestModules = find_test_modules(),
    Options = [verbose, no_tty,
               {report, {gleeunit_progress, [{colored, true}]}},
               {scale_timeouts, 10}],
    Result = eunit:test(TestModules, Options),

    report(),

    Code = case Result of
        ok -> 0;
        error -> 1;
        {error, _} -> 1
    end,
    erlang:halt(Code).

find_test_modules() ->
    Files = filelib:wildcard("**/*.{erl,gleam}", "test"),
    lists:map(fun(Path) ->
        Name = case lists:suffix(".gleam", Path) of
            true ->
                NoExt = lists:sublist(Path, length(Path) - 6),
                lists:map(fun($/) -> $@; (C) -> C end, NoExt);
            false ->
                Base = filename:basename(Path, ".erl"),
                Base
        end,
        list_to_atom(Name)
    end, Files).

report() ->
    io:format("~n===== CODE COVERAGE =====~n"),
    io:format("~-40s ~8s ~8s ~8s~n", [<<"Module">>, <<"Covered">>, <<"Total">>, <<"%">>]),
    io:format("~s~n", [lists:duplicate(68, $-)]),
    {TotalCov, TotalNot} = lists:foldl(fun(M, {AccC, AccN}) ->
        case cover:analyse(M, coverage, module) of
            {ok, {_, {Cov, NotCov}}} ->
                Total = Cov + NotCov,
                Pct = case Total of
                    0 -> 100.0;
                    _ -> Cov * 100.0 / Total
                end,
                Name = atom_to_binary(M),
                io:format("~-40s ~8B ~8B ~7.1f%~n", [Name, Cov, Total, Pct]),
                {AccC + Cov, AccN + NotCov};
            _ ->
                {AccC, AccN}
        end
    end, {0, 0}, modules()),
    GrandTotal = TotalCov + TotalNot,
    GrandPct = case GrandTotal of
        0 -> 100.0;
        _ -> TotalCov * 100.0 / GrandTotal
    end,
    io:format("~s~n", [lists:duplicate(68, $-)]),
    io:format("~-40s ~8B ~8B ~7.1f%~n", [<<"TOTAL">>, TotalCov, GrandTotal, GrandPct]),
    io:format("===========================~n~n"),
    nil.
