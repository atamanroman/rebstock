-module(zip_ffi).
-export([unzip_memory/1]).

unzip_memory(ZipBinary) ->
    case zip:unzip(ZipBinary, [memory]) of
        {ok, FileList} ->
            Converted = [{unicode:characters_to_binary(Name), Content}
                         || {Name, Content} <- FileList],
            {ok, Converted};
        {error, Reason} ->
            {error, Reason}
    end.
