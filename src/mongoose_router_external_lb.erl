%%%-------------------------------------------------------------------
%%% @doc
%%% Part of a routing chain; load balances traffic across several
%%% external components based on the bare To Jid
%%% @end
%%%-------------------------------------------------------------------

-module(mongoose_router_external_lb).
-author('igor.slepchin@gmail.com').

-behaviour(xmpp_router).

-include("mongoose_logger.hrl").
-include("jid.hrl").

%% xmpp_router callbacks
-export([filter/4, route/4]).

filter(From, To, Acc, Packet) ->
    {From, To, Acc, Packet}.

route(From, #jid{lserver = LServer} = To, Acc, Packet) ->
	case mod_component_lb:lookup_backend(From, To) of
		notfound ->
			{From, To, Acc, Packet};
		{Domain, Handler, _Node} ->
			?INFO_MSG("route to backend: ~p => ~p", [To, Domain]),
			mongoose_local_delivery:do_route(From, To, Acc, Packet, LServer, Handler),
			done
	end.
