-module(mongoose_elasticsearch).

-export([start/0]).
-export([stop/0]).
-export([health/0]).
-export([insert_document/4]).
-export([search/3]).
-export([count/3]).
-export([delete_by_query/3]).

-type index() :: binary().
-type type() :: binary().
-type document() :: map().
-type id() :: binary().
-type query() :: map().

-export_type([index/0]).
-export_type([type/0]).
-export_type([document/0]).
-export_type([id/0]).
-export_type([query/0]).

-include("mongoose.hrl").

-define(POOL_NAME, elasticsearch).

%%-------------------------------------------------------------------
%% API
%%-------------------------------------------------------------------

%% @doc Starts the pool of connections to ElasticSearch cluster.
%%
%% Currently connections are opened only to a single node.
-spec start() -> ignore | ok | no_return().
start() ->
    Opts = ejabberd_config:get_local_option(elasticsearch_server),
    case Opts of
        undefined ->
            ignore;
        _ ->
            tirerl:start(),
            start_pool(Opts)
    end.

%% @doc Stops the pool of connections to ElasticSearch cluster.
-spec stop() -> ok.
stop() ->
    stop_pool(),
    tirerl:stop().

%% @doc Returns the health status of the ElasticSearch cluster.
%%
%% See https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster-health.html for
%% more information.
-spec health() -> {ok, Resp :: map()} | {error, term()}.
health() ->
    case catch tirerl:health(?POOL_NAME) of
        {'EXIT', _} = Err ->
            {error, Err};
        Other ->
            Other
    end.

%% @doc Tries to insert a document into given ElasticSearch index.
%%
%% See https://www.elastic.co/guide/en/elasticsearch/reference/6.2/docs-index_.html for more
%% information.
-spec insert_document(index(), type(), id(), document()) -> {ok, Resp :: map()} | {error, term()}.
insert_document(Index, Type, Id, Document) ->
    case tirerl:insert_doc(?POOL_NAME, Index, Type, Id, Document) of
        {ok, #{<<"_id">> := Id}} = Resp ->
            Resp;
        {error, _} = Err ->
            Err
    end.

%% @doc Runs a search query on a given ElasticSearch index.
%%
%% See https://www.elastic.co/guide/en/elasticsearch/reference/6.2/search.html for more information.
-spec search(index(), type(), query()) -> {ok, Resp :: map()} | {error, term()}.
search(Index, Type, SearchQuery) ->
    tirerl:search(?POOL_NAME, Index, Type, SearchQuery).

%% @doc Retrieves count of documents matching given search query in given ElasticSearch index.
%%
%% See https://www.elastic.co/guide/en/elasticsearch/reference/6.2/search-count.html for more
%% information.
-spec count(index(), type(), query()) -> {ok, Count :: non_neg_integer()} | {error, term()}.
count(Index, Type, SearchQuery) ->
    case tirerl:count(?POOL_NAME, Index, Type, SearchQuery, []) of
        {ok, #{<<"count">> := Count}} when is_integer(Count), Count >= 0 ->
            {ok, Count};
        {error, _} = Err ->
            Err
    end.

%% @doc Deletes documents matching a query in a given ElasticSearch index.
%%
%% See https://www.elastic.co/guide/en/elasticsearch/reference/6.2/docs-delete-by-query.html for
%% more information.
-spec delete_by_query(index(), type(), query()) -> ok | {error, term()}.
delete_by_query(Index, Type, SearchQuery) ->
    case tirerl:delete_by_query(?POOL_NAME, Index, Type, SearchQuery, []) of
        {ok, _} ->
            ok;
        {error, _} = Err ->
            Err
    end.

%%-------------------------------------------------------------------
%% Helpers
%%-------------------------------------------------------------------

-spec start_pool(list()) -> ok | no_return().
start_pool(Opts) ->
    Host = proplists:get_value(host, Opts, "localhost"),
    Port = proplists:get_value(port, Opts, 9200),
    case tirerl:start_pool(?POOL_NAME, [{host, list_to_binary(Host)}, {port, Port}]) of
        {ok, _} ->
            ?INFO_MSG("Started pool of connections to ElasticSearch at ~p:~p",
                          [Host, Port]),
            ok;
        {ok, _, _} ->
            ?INFO_MSG("Started pool of connections to ElasticSearch at ~p:~p",
                          [Host, Port]),
            ok;
        {error, {already_started, _}} ->
            ?INFO_MSG("Pool of connections to ElasticSearch is already started", []),
            ok;
        {error, _} = Err ->
            ?ERROR_MSG("Failed to start pool of connections to ElasticSearch at ~p:~p: ~p",
                       [Host, Port, Err]),
            error(Err)
    end.

-spec stop_pool() -> any().
stop_pool() ->
    tirerl:stop_pool(?POOL_NAME).

