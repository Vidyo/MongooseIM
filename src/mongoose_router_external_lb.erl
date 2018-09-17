%%%-------------------------------------------------------------------
%%% @doc
%%% Part of a routing chain; load balances traffic across several
%%% external components based on the bare To Jid
%%% @end
%%%-------------------------------------------------------------------

-module(mongoose_router_external_lb).
-author('igor.slepchin@gmail.com').

-define(MUC, <<"muc.localhost">>).
-define(MUC1, <<"muc1.localhost">>).

-behaviour(xmpp_router).

-include("mongoose.hrl").
-include("jlib.hrl").
-include("external_component.hrl").
-include("mod_component_lb.hrl").
%% xmpp_router callback
-export([filter/4, route/4]).

filter(From, To, Acc, Packet) ->
    {From, To, Acc, Packet}.

route(From, #jid{lserver = LServer} = To, Acc, Packet) ->
	case mod_component_lb:get_backends(LServer) of
		error ->
			{From, To, Acc, Packet};
		{ok, Backends} ->
			route_to_backend(Backends, From, To, Acc, Packet)
	end;
route(From, To, Acc, Packet) ->
	{From, To, Acc, Packet}.

route_to_backend(Backends, From, #jid{luser = LUser} = To, Acc, Packet) ->
	?INFO_MSG("To LUser: ~p", [LUser]),
	case LUser of
		<<"">> ->
			route_transient_to_backend(Backends, From, To, Acc, Packet);
		_ ->
			route_persistent_to_backend(Backends, From, To, Acc, Packet)
	end.

route_transient_to_backend(Backends, #jid{luser = LUser} = From, #jid{lserver = LServer} = To, Acc, Packet) ->
	case get_random_backend(Backends, LUser) of
		{Domain, Handler} ->
			?INFO_MSG("route transient ~p => ~p", [To, Domain]),
			mongoose_local_delivery:do_route(From, To, Acc, Packet, LServer, Handler),
			done;
		{From, To, Acc, Packet} ->
			{From, To, Acc, Packet}
	end.

route_persistent_to_backend(Backends, From, #jid{luser = LUser, lserver = LServer} = To, Acc, Packet) ->
	Key = get_lookup_key(LUser, LServer),
	case mnesia:dirty_read(component_lb, Key) of
		[#component_lb{key = Key, backend = Backend, handler = Handler}] ->
			?INFO_MSG("found backend in mnesia: ~p => ~p", [Key, {Backend, Handler}]),
			mongoose_local_delivery:do_route(From, To, Acc, Packet, LServer, Handler),
			done;
		[] ->
			case get_random_backend(Backends, LUser) of
				{Domain, Handler} ->
					Record = #component_lb{key=Key, backend=Domain, handler=Handler},
					{atomic, _} = mnesia:transaction(fun () -> mnesia:write(Record) end),
					?INFO_MSG("inserted backend to mnesia: ~p => ~p", [Key, Record]),
					mongoose_local_delivery:do_route(From, To, Acc, Packet, LServer, Handler),
					done;
				{From, To, Acc, Packet} ->
					{From, To, Acc, Packet}
			end;
		Any ->
			?ERROR_MSG("Unexpected mnesia lookup result: ~p", [Any]),
			Handler = foo,
			error
	end.
	%% %% [#external_component{handler = Handler}|_] = Backend,
	%% mongoose_local_delivery:do_route(From, To, Acc, Packet, LServer, Handler),
	%% done.

get_lookup_key(LUser, LServer) ->
	{LUser, LServer}.

get_random_backend(Backends, LUser) ->
	%% Key = get_lookup_key(LUser, LServer),
	Backends1 = lists:map(fun ejabberd_router:lookup_component/1, Backends),
	ActiveBackends = lists:filter(fun(Backend) -> Backend /= [] end,
								  Backends1),
	case ActiveBackends of
		[] -> [];
		_  ->
			N = erlang:phash2(LUser, length(ActiveBackends)),
			[Backend|_] = lists:nth(N+1, ActiveBackends),
			#external_component{domain = Domain, handler = Handler} = Backend,
			{Domain, Handler}
	end.
