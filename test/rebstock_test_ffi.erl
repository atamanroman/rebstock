-module(rebstock_test_ffi).
-export([create_zip/1]).

create_zip(Files) ->
    ErlFiles = [{binary_to_list(Name), unicode:characters_to_binary(Content)}
                || {Name, Content} <- Files],
    {ok, {_, ZipBin}} = zip:create("test.zip", ErlFiles, [memory]),
    ZipBin.
