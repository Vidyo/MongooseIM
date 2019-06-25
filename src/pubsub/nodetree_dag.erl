%%% XEP-0248: PubSub Collection Nodes
%%% DAG stands for Directed Acyclic Graph
%%%
%%% ====================================================================
%%% ``The contents of this file are subject to the Erlang Public License,
%%% Version 1.1, (the "License"); you may not use this file except in
%%% compliance with the License. You should have received a copy of the
%%% Erlang Public License along with this software. If not, it can be
%%% retrieved via the world wide web at http://www.erlang.org/.
%%%
%%%
%%% Software distributed under the License is distributed on an "AS IS"
%%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%%% the License for the specific language governing rights and limitations
%%% under the License.
%%%
%%%
%%% @author Brian Cully <bjc@kublai.com>
%%% @version {@vsn}, {@date} {@time}
%%% @end
%%% ====================================================================

-module(nodetree_dag).
-behaviour(gen_pubsub_nodetree).
-author('bjc@kublai.com').

-include_lib("stdlib/include/qlc.hrl").

-include("pubsub.hrl").
-include("jlib.hrl").

-export([init/3, terminate/2, set_node/2,
         get_node/3, get_node/2, get_nodes/3,
         get_parentnodes_tree/4,
         get_subnodes/4, create_node/7,
         delete_node/3]).

-define(DEFAULT_NODETYPE, leaf).
-define(DEFAULT_PARENTS, []).
-define(DEFAULT_CHILDREN, []).

init(Host, ServerHost, Opts) ->
    nodetree_tree:init(Host, ServerHost, Opts).

terminate(Host, ServerHost) ->
    nodetree_tree:terminate(Host, ServerHost).

set_node(Backend, #pubsub_node{nodeid = {Key, _}, owners = Owners, options = Options} = Node) ->
    Parents = find_opt(collection, ?DEFAULT_PARENTS, Options),
    case validate_parentage(Backend, Key, Owners, Parents) of
        true -> Backend:set_node(Node#pubsub_node{parents = Parents});
        Other -> Other
    end.

create_node(Backend, Key, Node, Type, Owner, Options, Parents) ->
    OwnerJID = jid:to_lower(jid:to_bare(Owner)),
    case Backend:find_node_by_name(Key, Node) of
        false ->
            N = #pubsub_node{nodeid = {Key, Node},
                    type = Type, parents = Parents, owners = [OwnerJID],
                    options = Options},
            set_node(Backend, N);
        _ ->
            {error, mongoose_xmpp_errors:conflict()}
    end.

delete_node(Backend, Key, Node) ->
    case Backend:find_node_by_name(Key, Node) of
        false ->
            {error, mongoose_xmpp_errors:item_not_found()};
        Record ->
            lists:foreach(fun (#pubsub_node{options = Opts} = Child) ->
                        NewOpts = remove_config_parent(Node, Opts),
                        Parents = find_opt(collection, ?DEFAULT_PARENTS, NewOpts),
                        {ok, _} = Backend:set_node(
                                    Child#pubsub_node{parents = Parents,
                                                      options = NewOpts})
                end,
                get_subnodes(Backend, Key, Node)),
            Backend:delete_node(Record),
            [Record]
    end.

get_node(Backend, Key, Node) ->
    case Backend:find_node_by_name(Key, Node) of
        false -> {error, mongoose_xmpp_errors:item_not_found()};
        Record -> Record
    end.

get_node(Backend, Node) ->
    nodetree_tree:get_node(Backend, Node).

get_nodes(Backend, Key, From) ->
    nodetree_tree:get_nodes(Backend, Key, From).

get_parentnodes_tree(Backend, Key, Node, _From) ->
    Backend:get_parentnodes_tree(Key, Node).

get_subnodes(Backend, Host, Node, _From) ->
    get_subnodes(Backend, Host, Node).

get_subnodes(Backend, Host, <<>>) ->
    Backend:get_subnodes(Host, <<>>);

get_subnodes(Backend, Host, Node) ->
    case Backend:find_node_by_name(Host, Node) of
        false -> {error, mongoose_xmpp_errors:item_not_found()};
        _ -> Backend:get_subnodes(Host, Node)
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%% Key     = jid:jid() | host()
%% Default = term()
%% Options = [{Key = atom(), Value = term()}]
find_opt(Key, Default, Options) ->
    case lists:keysearch(Key, 1, Options) of
        {value, {Key, Val}} -> Val;
        _ -> Default
    end.

remove_config_parent(Node, Options) ->
    remove_config_parent(Node, Options, []).

remove_config_parent(_Node, [], Acc) ->
    lists:reverse(Acc);
remove_config_parent(Node, [{collection, Parents} | T], Acc) ->
    remove_config_parent(Node, T, [{collection, lists:delete(Node, Parents)} | Acc]);
remove_config_parent(Node, [H | T], Acc) ->
    remove_config_parent(Node, T, [H | Acc]).

-spec validate_parentage(
        Backend :: module(), 
        Key            :: mod_pubsub:hostPubsub(),
        Owners         :: [jid:ljid(), ...],
        ParentNodes    :: [mod_pubsub:nodeId()])
    -> true | {error, exml:element()}.
validate_parentage(_Backend, _Key, _Owners, []) ->
    true;
validate_parentage(Backend, Key, Owners, [[] | T]) ->
    validate_parentage(Backend, Key, Owners, T);
validate_parentage(Backend, Key, Owners, [<<>> | T]) ->
    validate_parentage(Backend, Key, Owners, T);
validate_parentage(Backend, Key, Owners, [ParentID | T]) ->
    case Backend:find_node_by_name(Key, ParentID) of
        false ->
            {error, mongoose_xmpp_errors:item_not_found()};
        #pubsub_node{owners = POwners, options = POptions} ->
            NodeType = find_opt(node_type, ?DEFAULT_NODETYPE, POptions),
            MutualOwners = [O || O <- Owners, PO <- POwners, O == PO],
            case {MutualOwners, NodeType} of
                {[], _} -> {error, mongoose_xmpp_errors:forbidden()};
                {_, collection} -> validate_parentage(Backend, Key, Owners, T);
                {_, _} -> {error, mongoose_xmpp_errors:not_allowed()}
            end
    end.
