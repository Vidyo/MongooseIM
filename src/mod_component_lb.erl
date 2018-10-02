-module(mod_component_lb).
-author('igor.slepchin@gmail.com').

-behavior(gen_server).
-behavior(gen_mod).

-include("mongoose.hrl").
-include("mongoose_ns.hrl").
-include("jid.hrl").
-include("jlib.hrl").
-include("external_component.hrl").

-define(lookup_key(LUser, LServer), {LUser, LServer}).
-define(DEFAULT_PING_INTERVAL, timer:seconds(10*60)).
-define(DEFAULT_PING_TIMEOUT, timer:seconds(20)).
-define(DEFAULT_TX_RETRIES, 2).

%% API
-export([start_link/2, lookup_backend/2]).

%% gen_mod callbacks
-export([start/2, stop/1]).

%% gen_server callbacks
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2,
         code_change/3]).

%% Hooks callbacks
-export([node_cleanup/2, unregister_subhost/2]).

-record(state, {lb = maps:new(),      %% frontend => backends map
                timers = maps:new(),
                ping_interval = ?DEFAULT_PING_INTERVAL,
                ping_timeout = ?DEFAULT_PING_TIMEOUT,
                tx_retries = ?DEFAULT_TX_RETRIES,
                host = <<"">>}).
-record(component_lb, {key, backend, handler, node}).

-type state() :: #state{}.
-type component_lb() :: #component_lb{}.
-type timers() :: #{jid:jid() := {reference(), component_lb()}}.
-type key() :: {LUser :: binary(), LServer :: binary()}.

%%====================================================================
%% API
%%====================================================================
start_link(Host, Opts) ->
    Proc = ?MODULE,
    ?INFO_MSG("event=start_link host=~p proc=~p", [Host, Proc]),
    gen_server:start_link({local, Proc}, ?MODULE, [Host, Opts], []).

-spec lookup_backend(From :: jid:jid(), To :: jid:jid()) -> binary() | notfound.
lookup_backend(From, #jid{lserver = LServer} = To) ->
	case get_backends(LServer) of
		error ->
			notfound;
		{ok, Backends} ->
			lookup_backend(Backends, From, To)
	end.

%%====================================================================
%% Hooks callbacks
%%====================================================================
node_cleanup(Acc, Node) ->
	?WARNING_MSG("event=node_cleanup node=~p", [Node]),
	delete_node(Node),
	Acc.

unregister_subhost(Acc, LDomain) ->
	?WARNING_MSG("event=unregister_subhost subhost=~p", [LDomain]),
	delete_backend(LDomain),
	Acc.

%%====================================================================
%% gen_mod callbacks
%%====================================================================
start(Host, Opts) ->
	?DEBUG("event=start host=~p opts=~p)", [Host, Opts]),
	Proc = gen_mod:get_module_proc(Host, ?MODULE),
	ChildSpec = #{id=>Proc, start=>{?MODULE, start_link, [Host, Opts]},
				  restart=>transient, shutdown=>2000,
				  type=>worker, modules=>[?MODULE]},
    {ok, _} = supervisor:start_child(ejabberd_sup, ChildSpec).

stop(Host) ->
    ?DEBUG("event=stop", []),
    Proc = gen_mod:get_module_proc(Host, ?MODULE),
    supervisor:terminate_child(ejabberd_sup, Proc),
    supervisor:delete_child(ejabberd_sup, Proc).

%%====================================================================
%% gen_server callbacks
%%====================================================================
-spec init(Args :: list()) -> {ok, state()}.
init([Host, Opts]) ->
    State = process_opts(Opts, #state{host = Host}),
    ?INFO_MSG("event=init host=~p opts=~p state=~p", [Host, Opts, State]),
    mnesia:create_table(component_lb,
                        [{ram_copies, [node()]},
                         {type, set},
						 {index, [#component_lb.backend, #component_lb.node]},
						 {attributes, record_info(fields, component_lb)}]),
	mnesia:add_table_copy(key, node(), ram_copies),
	compile_dynamic_src(State),
	State1 = reload(State),
	ejabberd_hooks:add(node_cleanup, global, ?MODULE, node_cleanup, 90),
	ejabberd_hooks:add(unregister_subhost, global, ?MODULE, unregister_subhost, 90),
	{ok, State1}.

handle_call(Request, From, State) ->
	?WARNING_MSG("event=handle_call_unexpected request=~p from=~p", [Request, From]),
	{reply, error, State}.

handle_cast({start_ping, JID, Record}, State) ->
    Timers = add_timer(JID, Record, State#state.ping_interval, State#state.timers),
    {noreply, State#state{timers = Timers}};

handle_cast({iq_pong, JID, Record, timeout}, State) ->
	?WARNING_MSG("event=room_ping_timeout jid=~p", [JID]),
	State1 = delete_record(JID, Record, State),
	{noreply, State1};
handle_cast({iq_pong, JID, Record, #iq{type = error} = Response}, State) ->
	?INFO_MSG("event=room_ping_error jid=~p response=~p", [JID, Response]),
	State1 = delete_record(JID, Record, State),
	{noreply, State1};
handle_cast({iq_pong, _Record, _JID, _Response}, State) ->
	{noreply, State};

handle_cast(Request, State) ->
	?WARNING_MSG("event=handle_cast_unexpected request=~p", [Request]),
	{noreply, State}.

handle_info({timeout, _TRef, {ping, #jid{luser = LUser, lserver = LServer} = JID, Record}}, State) ->
    Key = ?lookup_key(LUser, LServer),
    case mnesia:dirty_read(component_lb, Key) of
        [Record] ->
            send_ping(JID, Record, State),
            Timers = add_timer(JID, Record, State#state.ping_interval, State#state.timers);
        [] ->
            Timers = del_timer(JID, Record, State#state.timers);
        NewRecord ->
            ?WARNING_MSG("event=room_ping_backend_record_changed from=~p to=~p", [Record, NewRecord]),
            Timers = del_timer(JID, Record, State#state.timers)
    end,
    State1 = State#state{timers = Timers},
    {noreply, State1};

handle_info(Info, State) ->
    ?WARNING_MSG("event=handle_cast_unexpected info=~p", [Info]),
    {noreply, State}.

terminate(Reason, _State) ->
    ?INFO_MSG("event=terminate reason=~p", [Reason]),
    ejabberd_hooks:delete(node_cleanup, global, ?MODULE, node_cleanup, 90),
    ejabberd_hooks:delete(unregister_subhost, global, ?MODULE, unregister_subhost, 90),
    delete_node(node()),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================
-spec start_ping(Node :: node(), JID :: jid:jid(), Record :: component_lb()) -> ok.
start_ping(Node, JID, Record) when JID#jid.lresource =:= <<>> ->
	?DEBUG("event=room_ping_start node=~p jid=~p", [Node, JID]),
	gen_server:cast({?MODULE, Node}, {start_ping, JID, Record}).

-spec send_ping(JID :: jid:jid(), Record :: component_lb(), State :: state()) -> mongoose_acc:t().
send_ping(JID, Record, State) ->
    ?DEBUG("event=room_ping_send jid=~p", [JID]),
    IQ = #iq{type = get,
             sub_el = [#xmlel{name = <<"query">>,
                              attrs = [{<<"xmlns">>, ?NS_DISCO_ITEMS}]}]},
    Pid = self(),
    F = fun(Response) ->
                gen_server:cast(Pid, {iq_pong, JID, Record, Response})
        end,
    From = jid:make(<<"">>, State#state.host, <<"">>),
    Acc = mongoose_acc:from_element(IQ, From, JID),
    ejabberd_local:route_iq(From, JID, Acc, IQ, F, State#state.ping_timeout).

-spec add_timer(JID :: jid:jid(), Record :: component_lb(),
                Interval :: non_neg_integer(), Timers :: timers()) -> timers().
add_timer(JID, Record, Interval, Timers) ->
    NewTimers = case maps:find(JID, Timers) of
                    {ok, {OldTRef, Record}} ->
                        cancel_timer(OldTRef),
                        maps:remove(JID, Timers);
                    {ok, {OldTRef, OldRecord}} ->
                        ?WARNING_MSG("event=room_ping_record_changed old=~p new=~p note=this_is_weird",
                                     [OldRecord, Record]),
                        cancel_timer(OldTRef),
                        maps:remove(JID, Timers);
                    _ ->
                        Timers
                end,
    TRef = erlang:start_timer(Interval, self(), {ping, JID, Record}),
    maps:put(JID, {TRef, Record}, NewTimers).

-spec del_timer(JID :: jid:jid(), Record :: component_lb(), Timers :: timers()) -> timers().
del_timer(JID, Record, Timers) ->
    case maps:find(JID, Timers) of
        {ok, {TRef, Record}} ->
            cancel_timer(TRef),
            maps:remove(JID, Timers);
        _ ->
            Timers
    end.

-spec cancel_timer(reference()) -> ok.
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

-spec delete_record(JID :: jid:jid(), component_lb(), state()) -> state().
delete_record(JID, Record, State) ->
    Timers = del_timer(JID, Record, State#state.timers),
    case mnesia:transaction(fun () -> mnesia:delete_object(Record) end) of
        {atomic, _} -> ok;
        {aborted, Reason} -> ?WARNING_MSG("event=record_delete_error record=~p reason=~p", [Record, Reason])
    end,
    State#state{timers = Timers}.

-spec get_backends(Frontend :: binary()) -> {ok, list()} | error.
get_backends(Frontend) ->
	mod_component_lb_dynamic:get_backends(Frontend).

-spec lookup_backend(Backends :: [binary()], From :: jid:jid(), To :: jid:jid()) -> binary() | notfound.
lookup_backend(Backends, From, #jid{luser = LUser} = To) ->
	case LUser of
		<<"">> ->
			lookup_backend_transient(Backends, From);
		_ ->
			lookup_backend_persistent(Backends, To)
	end.

-spec lookup_backend_transient(Backends :: [binary()], From :: jid:jid()) ->
                                      {Domain :: binary(), Handler :: any(), Node :: node()} | notfound.
lookup_backend_transient(Backends, #jid{luser = LUser} = _From) ->
	get_random_backend(Backends, LUser).

-spec lookup_backend_persistent(Backends :: [binary()], To :: jid:jid()) ->
                                      {Domain :: binary(), Handler :: any(), Node :: node()} | notfound.
lookup_backend_persistent(Backends, #jid{luser = LUser, lserver = LServer} = _To) ->
	Key = ?lookup_key(LUser, LServer),
	case mnesia:dirty_read(component_lb, Key) of
		[#component_lb{key = Key, backend = Domain, handler = Handler, node = Node}] ->
			?DEBUG("event=record_found_backend key=~p handler=~p", [Key, {Domain, Handler}]),
			{Domain, Handler, Node};
		[] ->
			case get_random_backend(Backends, LUser) of
				{Domain, Handler, Node} ->
					write_record(Key, Domain, Handler, Node);
				notfound ->
					notfound
			end;
		Any ->
			?ERROR_MSG("event=record_lookup_error result=~p", [Any]),
			error
	end.

-spec write_record(Key :: key(), Domain :: binary(), Handler :: any(), Node :: node()) ->
                          {Domain :: binary(), Handler :: any(), Node :: node()}.
write_record({LUser, LServer} = Key, Domain, Handler, Node) ->
	R = #component_lb{key=Key, backend=Domain, handler=Handler, node=Node},
	F = fun() ->
				case mnesia:read(component_lb, Key) of
					[] ->
						mnesia:write(R),
						R;
					[R1] ->
						mnesia:abort(R1) %% somebody else has added the record, just use it
				end
		end,
	TxRetries = mod_component_lb_dynamic:get_tx_retries(),
	case mnesia:transaction(F, TxRetries) of
		{atomic, R} ->
			?DEBUG("event=record_insert key=~p record=~p", [Key, R]),
			JID = jid:make(LUser, LServer, <<>>), %% we want to go to Domain directly!!
			start_ping(Node, JID, R),
			{Domain, Handler, Node};
		{aborted, #component_lb{backend = Domain1, handler = Handler1, node = Node1}} ->
			{Domain1, Handler1, Node1}
	end.

-spec get_random_backend(Backends :: [binary()], LUser :: binary()) ->
                                {Domain :: binary(), Handler :: any(), Node :: node()} | notfound.
get_random_backend(Backends, LUser) ->
	Backends1 = lists:map(fun ejabberd_router:lookup_component/1, Backends),
    ActiveBackends = lists:filter(fun(Backend) ->
                                          Backend /= []
                                  end,
                                  Backends1),
	case ActiveBackends of
		[] -> notfound;
		_  ->
			N = erlang:phash2(LUser, length(ActiveBackends)),
			% external_component_global stores a list for god knows what reason;
			% just grab the first one - that's what mongoose_router_external does
			[Backend|_] = lists:nth(N+1, ActiveBackends),
			#external_component{domain = Domain, handler = Handler, node = Node} = Backend,
			{Domain, Handler, Node}
	end.

-spec delete_backend(Backend :: binary()) -> ok.
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
    {atomic, _} = mnesia:transaction(F),
    ok.

-spec delete_node(Node :: node()) -> ok.
delete_node(Node) ->
	F = fun() ->
                mnesia:lock({table, component_lb}, write),
                Keys = mnesia:dirty_select(
                         component_lb,
                         [{#component_lb{node = '$1',  key = '$2', _ = '_'},
                           [{'==', '$1', Node}],
                           ['$2']}]),
                lists:foreach(fun(Key) ->
                                      mnesia:delete({component_lb, Key})
                              end, Keys)
        end,
    {atomic, _} = mnesia:transaction(F),
    ok.

process_opts([{lb, LBOpts}|Opts], State) ->
	State1 = process_lb_opt(LBOpts, State),
	process_opts(Opts, State1);
process_opts([{ping_interval, Value}|Opts], State) ->
    Sec = timer:seconds(Value),
    State1 = State#state{ping_interval = Sec},
    process_opts(Opts, State1);
process_opts([{ping_timeout, Value}|Opts], State) ->
    Sec = timer:seconds(Value),
    State1 = State#state{ping_timeout = Sec},
    process_opts(Opts, State1);
process_opts([{tx_retries, Value}|Opts], State) ->
    State1 = State#state{tx_retries = Value},
    process_opts(Opts, State1);
process_opts([Opt|Opts], State) ->
	?WARNING_MSG("event=config_unknown_option option=~p", [Opt]),
	process_opts(Opts, State);
process_opts([], State) ->
	State.

process_lb_opt({Frontend, Backends}, #state{lb = LBDomains} = State)
  when is_list(Backends) ->
	?INFO_MSG("event=config_lb_option frontend=~p backend=~p", [Frontend, Backends]),
    FrontendBin = list_to_binary(Frontend),
	BackendsBin = lists:map(fun erlang:list_to_binary/1, Backends),
	LBDomains1  = LBDomains#{FrontendBin => BackendsBin},
	State1      = State#state{lb = LBDomains1},
	?INFO_MSG("event=config_lb_state state=~p", [State1]),
	State1;
process_lb_opt(Opt, State) ->
	?WARNING_MSG("event=config_unknown_lb_opttion option=~p", [Opt]),
	State.

compile_dynamic_src(State) ->
    Source = mod_component_lb_dynamic_src(State),
    ?INFO_MSG("compile src: ~s", [Source]),
    {Module, Code} = dynamic_compile:from_string(Source),
    code:load_binary(Module, "mod_component_lb_dynamic.erl", Code),
    ok.

mod_component_lb_dynamic_src(#state{lb = Frontends, tx_retries = TxRetries} = _State) ->
    lists:flatten(
        ["-module(mod_component_lb_dynamic).
         -export([get_backends/1, get_tx_retries/0]).

         get_tx_retries() ->
             ", io_lib:format("~p", [TxRetries]), ".

         get_backends(Domain) ->
             ", io_lib:format("maps:find(Domain, ~p)", [Frontends]), ".\n"]).

-spec reload(State :: state()) -> state().
reload(State) ->
    %% TODO: iterate instead of grabbing all records in one go
    Records = mnesia:dirty_select(
                component_lb,
                [{#component_lb{node = '$1', key = '$2', _ = '_'},
                  [{'==', '$1', node()}],
                  ['$_']}]),
    lists:foldl(fun(Record, S) ->
                        reload(Record, S)
                end, State, Records).

-spec reload(Record :: component_lb(), State :: state()) -> state().
reload(#component_lb{key = {LUser, LServer}} = Record, #state{timers = Timers} = State) ->
    JID = jid:make(LUser, LServer, <<>>),
    case maps:find(JID, Timers) of
        {ok, {_TRef, Record}} ->
            Timers1 = Timers;
        _ ->
            Interval = rand:uniform(State#state.ping_interval),
            Timers1 = add_timer(JID, Record, Interval, Timers)
    end,
    State#state{timers = Timers1}.
