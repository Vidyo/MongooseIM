-module(mod_component_lb).
-author('igor.slepchin@gmail.com').

-behavior(gen_server).
-behaviour(gen_mod).

-include("mongoose.hrl").
-include("mongoose_ns.hrl").
-include("jid.hrl").
-include("jlib.hrl").
-include("external_component.hrl").

%% API
-export([start_link/2, lookup_backend/2]).

%% gen_mod callbacks
-export([start/2, stop/1]).

%% gen_server callbacks
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2,
         code_change/3]).

%% Hooks callbacks
-export([node_cleanup/2, unregister_subhost/2]).

-record(state, {lb = #{},
				timers = maps:new(),
				host}).
-record(component_lb, {key, backend, handler, node}).

-define(lookup_key(LUser, LServer), {LUser, LServer}).
-define(PING_INTERVAL, 5000).
-define(PING_REQ_TIMEOUT, ?PING_INTERVAL div 2).

%%====================================================================
%% API
%%====================================================================
start_link(Host, Opts) ->
    Proc = ?MODULE,
	?INFO_MSG("start_link: host ~p, proc ~p", [Host, Proc]),
    gen_server:start_link({local, Proc}, ?MODULE, [Host, Opts], []).

lookup_backend(From, #jid{lserver = LServer} = To) ->
	case get_backends(LServer) of
		error ->
			?DEBUG("backend not found for ~p", [LServer]),
			[];
			%% {From, To, Acc, Packet};
		{ok, Backends} ->
			lookup_backend(Backends, From, To)
	end.

%%====================================================================
%% Hooks callbacks
%%====================================================================

node_cleanup(Acc, Node) ->
	?INFO_MSG("component_lb node_cleanup for ~p", [Node]),
	{node, Backend} = Node,
	delete_backend(Backend),
	Acc.

unregister_subhost(Acc, LDomain) ->
	?INFO_MSG("component_lb unregister_subhost for ~p", [LDomain]),
	delete_backend(LDomain),
	Acc.

delete_backend(Backend) ->
	F = fun() ->
				mnesia:lock({table, component_lb}, write),
                Keys = mnesia:dirty_select(
                         component_lb,
                         [{#component_lb{backend = '$1',  key = '$2', _ = '_'},
                           [{'==', '$1', Backend}],
                           ['$2']}]),
                lists:foreach(fun(Key) ->
                                      mnesia:delete({component_lb, Key})
                              end, Keys)
        end,
    {atomic, _} = mnesia:transaction(F).

%% mnesia:dirty_select(component_lb, [{#component_lb{backend = '$1',  key = '$2', _ = '_'}, [{'==', '$1', Backend}], ['$2']}])

% Keys = mnesia:dirty_select(foo, [{#foo{bar = '$1', _ = '_'}, [], ['$1']}])
% lists:foreach(fun(Key) -> mnesia:delete({foo, Key}) end, Keys)

%%====================================================================
%% gen_mod callbacks
%%====================================================================
start(Host, Opts) ->
	?INFO_MSG("start", []),
	Proc = gen_mod:get_module_proc(Host, ?MODULE),
	ChildSpec = #{id=>Proc, start=>{?MODULE, start_link, [Host, Opts]},
				  restart=>transient, shutdown=>2000,
				  type=>worker, modules=>[?MODULE]},
    ejabberd_sup:start_child(ChildSpec).

stop(Host) ->
	?INFO_MSG("stop", []),
    Proc = gen_mod:get_module_proc(Host, ?MODULE),
    ejabberd_sup:stop_child(Proc).

%%====================================================================
%% gen_server callbacks
%%====================================================================
%% -spec init(Args :: list()) -> {ok, state()}.
init([Host, Opts]) ->
	?INFO_MSG("~p: ~p", [Host, Opts]),
	State = #state{host = Host},
	State1 = process_opts(Opts, State),
	?INFO_MSG("LB State: ~p", [State1]),
    mnesia:create_table(component_lb,
                        [{ram_copies, [node()]},
                         {type, set},
						 {index, [#component_lb.backend]},
						 {attributes, record_info(fields, component_lb)}]),
	mnesia:add_table_copy(key, node(), ram_copies),
	compile_frontends(State1#state.lb),
	ejabberd_hooks:add(node_cleanup, global, ?MODULE, node_cleanup, 90),
	ejabberd_hooks:add(unregister_subhost, global, ?MODULE, unregister_subhost, 90),
	{ok, State1}.

handle_call(Request, From, State) ->
	?WARNING_MSG("Unexpected gen_server call: ~p", [[Request, From, State]]),
	{reply, error, State}.
%% handle_call({frontend, Domain}, _From, #state{backends = Backends} = State) ->
%% 	%% ?DEBUG("frontends for ~p", [Domain]),
%% 	{reply, maps:find(Domain, Backends), State}.
%% %% handle_call(stop, _From, State) ->
%% %% 	?INFO_MSG("stop"),
%% %% 	{stop, normal, ok, State}.

handle_cast({start_ping, JID}, State) ->
    Timers = add_timer(JID, ?PING_INTERVAL, State#state.timers),
    {noreply, State#state{timers = Timers}};

handle_cast({iq_pong, JID, timeout}, State) ->
	?WARNING_MSG("backend ping timeout on ~p", [JID]),
	State1 = delete_record(JID, State),
	{noreply, State1};
handle_cast({iq_pong, JID, #iq{type = error} = Response}, State) ->
	?WARNING_MSG("backend ping error response on ~p: ~p", [JID, Response]),
	State1 = delete_record(JID, State),
	{noreply, State1};
handle_cast({iq_pong, _JID, _Response}, State) ->
	{noreply, State};

handle_cast(Request, State) ->
	?INFO_MSG("handle_cast: ~p, ~p", [Request, State]),
	{noreply, State}.

handle_info({timeout, _TRef, {ping, JID}}, State) ->
	?INFO_MSG("Sending ping disco to ~p", [JID]),
    IQ = #iq{type = get,
             sub_el = [#xmlel{name = <<"query">>,
                              attrs = [{<<"xmlns">>, ?NS_DISCO_INFO}]}]},
    Pid = self(),
    F = fun(_From, _To, Acc, Response) ->
                gen_server:cast(Pid, {iq_pong, JID, Response}),
                Acc
        end,
    From = jid:make(<<"">>, State#state.host, <<"">>),
    Acc = mongoose_acc:from_element(IQ, From, JID),
	?INFO_MSG("Routing ping disco to ~p", [JID]),
    ejabberd_local:route_iq(From, JID, Acc, IQ, F, ?PING_REQ_TIMEOUT),
	Timers = add_timer(JID, ?PING_INTERVAL, State#state.timers),
    {noreply, State#state{timers = Timers}};
handle_info(Info, State) ->
	?INFO_MSG("handle_info: ~p", [Info]),
    {noreply, State}.

terminate(_Reason, #state{host = Host} = State) ->
	?INFO_MSG("mod_component_lb:terminate", []),
    ejabberd_hooks:delete(node_cleanup, global, ?MODULE, node_cleanup, 90),
	ejabberd_hooks:delete(unregister_subhost, global, ?MODULE, unregister_subhost, 90),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

start_ping(Host, Node, JID) when JID#jid.lresource =:= <<>> ->
	?INFO_MSG("start_ping: ~p, ~p, ~p", [Host, Node, JID]),
	gen_server:cast({?MODULE, Node}, {start_ping, JID}).

%% stop_ping(Host, JID) ->
%%     gen_server:cast(?MODULE, {stop_ping, JID}).

add_timer(JID, Interval, Timers) ->
    LJID = jid:to_lower(JID),
    NewTimers = case maps:find(LJID, Timers) of
                    {ok, OldTRef} ->
                        cancel_timer(OldTRef),
                        maps:remove(LJID, Timers);
                    _ ->
                        Timers
                end,
    TRef = erlang:start_timer(Interval, self(), {ping, JID}),
    maps:put(LJID, TRef, NewTimers).

del_timer(JID, Timers) ->
    LJID = jid:to_lower(JID),
    case maps:find(LJID, Timers) of
        {ok, TRef} ->
            cancel_timer(TRef),
            maps:remove(LJID, Timers);
        _ ->
            Timers
    end.

cancel_timer(TRef) ->
    case erlang:cancel_timer(TRef) of
        false ->
            receive
                {timeout, TRef, _} ->
                    ok
            after 0 ->
                      ok
            end;
        _ ->
            ok
    end.

delete_record(#jid{luser = LUser, lserver = LServer} = JID, State) ->
	Timers = del_timer(JID, State#state.timers),
	Key = ?lookup_key(LUser, LServer),
	{atomic, _} = mnesia:transaction(fun () -> mnesia:delete({component_lb, Key}) end),
    State#state{timers = Timers}.

get_backends(Domain) ->
	mod_component_lb_dynamic:get_backends(Domain).

lookup_backend(Backends, From, #jid{luser = LUser} = To) ->
	case LUser of
		<<"">> ->
			lookup_backend_transient(Backends, From);
		_ ->
			lookup_backend_persistent(Backends, To)
	end.

lookup_backend_transient(Backends, #jid{luser = LUser} = From) ->
	get_random_backend(Backends, LUser).

lookup_backend_persistent(Backends, #jid{luser = LUser, lserver = LServer} = To) ->
	Key = ?lookup_key(LUser, LServer),
	case mnesia:dirty_read(component_lb, Key) of
		[#component_lb{key = Key, backend = Domain, handler = Handler, node = Node}] ->
			?INFO_MSG("found backend in mnesia: ~p => ~p", [Key, {Domain, Handler}]),
			{Domain, Handler, Node};
			%% mongoose_local_delivery:do_route(From, To, Acc, Packet, LServer, Handler),
			%% done;
		[] ->
			case get_random_backend(Backends, LUser) of
				{Domain, Handler, Node} ->
					Record = #component_lb{key=Key, backend=Domain, handler=Handler, node=Node},
					{atomic, _} = mnesia:transaction(fun () -> mnesia:write(Record) end),
					?INFO_MSG("inserted backend to mnesia: ~p => ~p", [Key, Record]),
					JID = jid:make(LUser, LServer, <<>>),
					start_ping(ok, Node, JID),
					{Domain, Handler, Node};
					%% mongoose_local_delivery:do_route(From, To, Acc, Packet, LServer, Handler),
					%% done;
				[] ->
					[]
			end;
		Any ->
			?ERROR_MSG("Unexpected mnesia lookup result: ~p", [Any]),
			error
	end.

get_random_backend(Backends, LUser) ->
	Backends1 = lists:map(fun ejabberd_router:lookup_component/1, Backends),
	ActiveBackends = lists:filter(fun(Backend) -> Backend /= [] end,
								  Backends1),
	case ActiveBackends of
		[] -> [];
		_  ->
			N = erlang:phash2(LUser, length(ActiveBackends)),
			% external_component_global stores a list for god knows what reason;
			% just grab the first one - that's what mongoose_router_external does
			[Backend|_] = lists:nth(N+1, ActiveBackends),
			#external_component{domain = Domain, handler = Handler, node = Node} = Backend,
			{Domain, Handler, Node}
	end.

process_opts([{lb, LBOpts}|Opts], State) ->
	State1 = process_lb_opt(LBOpts, State),
	process_opts(Opts, State1);
process_opts([Opt|Opts], State) ->
	?WARNING_MSG("unknown opt: ~p", [Opt]),
	process_opts(Opts, State);
process_opts([], State) ->
	State.

process_lb_opt({Frontend, Backends}, #state{lb = LBDomains} = State)
  when is_list(Backends) ->
	?INFO_MSG("lb opt: ~p => ~p", [Frontend, Backends]),
    FrontendBin = list_to_binary(Frontend),
	BackendsBin = lists:map(fun erlang:list_to_binary/1, Backends),
	LBDomains1  = LBDomains#{FrontendBin => BackendsBin},
	State1      = State#state{lb = LBDomains1},
	?INFO_MSG("lb opt state: ~p", [State1]),
	State1;
process_lb_opt(Opt, State) ->
	?WARNING_MSG("unknown lb opt: ~p", [Opt]),
	State.

compile_frontends(Frontends) ->
    Source = mod_component_lb_dynamic_src(Frontends),
	?INFO_MSG("dynamic src: ~s", [Source]),
    {Module, Code} = dynamic_compile:from_string(Source),
    code:load_binary(Module, "mod_component_lb_dynamic.erl", Code),
    ok.

mod_component_lb_dynamic_src(Frontends) ->
    lists:flatten(
        ["-module(mod_component_lb_dynamic).
         -export([get_backends/1]).

         get_backends(Domain) ->
             ", io_lib:format("maps:find(Domain, ~p)", [Frontends]), ".\n"]).
