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

route_to_backend(Backends, From, #jid{luser = LUser, lserver = LServer} = To, Acc, Packet) ->
	Key = get_lookup_key(LUser, LServer),
	case mnesia:dirty_read(component_lb, Key) of
		[#component_lb{key = Key, backend = Backend, handler = Handler}] ->
			?INFO_MSG("found backend in mnesia: ~p => ~p", [Key, {Backend, Handler}]),
			Handler,
			mongoose_local_delivery:do_route(From, To, Acc, Packet, LServer, Handler),
			done;
		[] ->
			Backends1 = lists:map(fun ejabberd_router:lookup_component/1, Backends),
			ActiveBackends = lists:filter(fun(Backend) -> Backend /= [] end,
										  Backends1),
			case ActiveBackends of
				[] ->
					?WARNING_MSG("No active backends for ~p", [LServer]),
					{From, To, Acc, Packet};
				_ ->
					N = erlang:phash2(LUser, length(ActiveBackends)),
					[Backend|_] = lists:nth(N+1, ActiveBackends),
					?INFO_MSG("Chose backend: ~p", [Backend]),
					#external_component{domain = Domain, handler = Handler} = Backend,
					Record = #component_lb{key=Key, backend=Domain, handler=Handler},
					{atomic, _} = mnesia:transaction(fun () -> mnesia:write(Record) end),
					?INFO_MSG("inserted backend to mnesia: ~p => ~p", [Key, Record]),
					Handler,
					mongoose_local_delivery:do_route(From, To, Acc, Packet, LServer, Handler),
					done
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

	%%     case ejabberd_router:lookup_component(LDstDomain) of
    %%     [] ->
    %%         {From, To, Acc, Packet};
    %%     [#external_component{handler = Handler}|_] -> %% may be multiple on various nodes
    %%         mongoose_local_delivery:do_route(From, To, Acc, Packet,
    %%             LDstDomain, Handler),
    %%         done
    %% end;

%% route(From, #jid{lserver = ?MUC} = To, Acc, Packet) ->
%% 	To1 = To#jid{lserver = ?MUC1, server = ?MUC1},
%% 	?INFO_MSG("LB rewrite To from ~p to ~p", [To, To1]),
%% 	{From, To1, Acc, Packet};
%% route(#jid{lserver = ?MUC1, luser = LUser} = From, To, Acc, Packet) ->
%% 	case LUser of
%% 		<<>> ->
%% 			{From, To, Acc, Packet};
%% 		_ ->
%% 			From1 = From#jid{lserver = ?MUC, server = ?MUC},
%% 			?INFO_MSG("LB rewrite From from ~p to ~p", [From, From1]),
%% 			{From1, To, Acc, Packet}
%% 	end;
%% route(From, To, Acc, Packet) ->
%% 	?DEBUG("To: ~p, From: ~p", [To, From]),
%% 	{From, To, Acc, Packet}.
