-module(vidyo_cowboy_static).
-author('igor.slepchin@gmail.com').

%% Just like cowboy_static but inserts CORS header in the response

-export([init/3]).
-export([rest_init/2]).
-export([malformed_request/2]).
-export([forbidden/2]).
-export([content_types_provided/2]).
-export([resource_exists/2]).
-export([last_modified/2]).
-export([generate_etag/2]).
-export([get_file/2]).

init(Foo, Bar, Baz) ->
    cowboy_static:init(Foo, Bar, Baz).

rest_init(Req, Opts) ->
    Req1 = cowboy_req:set_resp_header(<<"access-control-allow-origin">>, <<"*">>, Req),
    cowboy_static:rest_init(Req1, Opts).

malformed_request(Req, State) ->
    cowboy_static:malformed_request(Req, State).

forbidden(Req, State) ->
    cowboy_static:forbidden(Req, State).

content_types_provided(Req, State) ->
    cowboy_static:content_types_provided(Req, State).

resource_exists(Req, State) ->
    cowboy_static:resource_exists(Req, State).

last_modified(Req, State) ->
    cowboy_static:last_modified(Req, State).

generate_etag(Req, State) ->
    cowboy_static:generate_etag(Req, State).

get_file(Req, State) ->
    cowboy_static:get_file(Req, State).
