-module(rebstock_ffi).
-export([timestamp_ms/0]).

timestamp_ms() ->
    os:system_time(millisecond).
