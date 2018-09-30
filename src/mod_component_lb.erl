-module(mod_component_lb).
-author('igor.slepchin@gmail.com').

-behavior(gen_server).
-behavior(gen_mod).

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

-type state() :: #state{}.
-type component_lb() :: #component_lb{}.
-type timers() :: #{jid:jid() := {reference(), component_lb()}}.

-define(lookup_key(LUser, LServer), {LUser, LServer}).
-define(PING_INTERVAL, 5000).
-define(PING_REQ_TIMEOUT, ?PING_INTERVAL div 2).
-define(TX_RETRIES, 2).

%%====================================================================
%% API
%%====================================================================
start_link(Host, Opts) ->
    Proc = ?MODULE,
	?INFO_MSG("start_link: host ~p, proc ~p", [Host, Proc]),
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
	?INFO_MSG("component_lb node_cleanup for ~p", [Node]),
	delete_node(Node),
	Acc.

unregister_subhost(Acc, LDomain) ->
	?INFO_MSG("component_lb unregister_subhost for ~p", [LDomain]),
	delete_backend(LDomain),
	Acc.

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
-spec init(Args :: list()) -> {ok, state()}.
init([Host, Opts]) ->
	?INFO_MSG("~p: ~p", [Host, Opts]),
	State = process_opts(Opts, #state{host = Host}),
	?INFO_MSG("LB State: ~p", [State]),
    mnesia:create_table(component_lb,
                        [{ram_copies, [node()]},
                         {type, set},
						 {index, [#component_lb.backend, #component_lb.node]},
						 {attributes, record_info(fields, component_lb)}]),
	mnesia:add_table_copy(key, node(), ram_copies),
	compile_frontends(State#state.lb),
	State1 = reload(State),
	ejabberd_hooks:add(node_cleanup, global, ?MODULE, node_cleanup, 90),
	ejabberd_hooks:add(unregister_subhost, global, ?MODULE, unregister_subhost, 90),
	{ok, State1}.

handle_call(Request, From, State) ->
	?WARNING_MSG("Unexpected gen_server call: ~p", [[Request, From, State]]),
	{reply, error, State}.
%% handle_call(stop, _From, State) ->
%% 	?INFO_MSG("stop"),
%% 	{stop, normal, ok, State}.

handle_cast({start_ping, JID, Record}, State) ->
    Timers = add_timer(JID, Record, ?PING_INTERVAL, State#state.timers),
    {noreply, State#state{timers = Timers}};

handle_cast({iq_pong, JID, Record, timeout}, State) ->
	?WARNING_MSG("backend ping timeout on ~p", [JID]),
	State1 = delete_record(JID, Record, State),
	{noreply, State1};
handle_cast({iq_pong, JID, Record, #iq{type = error} = Response}, State) ->
	?WARNING_MSG("backend ping error response on ~p: ~p", [JID, Response]),
	State1 = delete_record(JID, Record, State),
	{noreply, State1};
handle_cast({iq_pong, _Record, _JID, _Response}, State) ->
	{noreply, State};

handle_cast(Request, State) ->
	?INFO_MSG("handle_cast: ~p, ~p", [Request, State]),
	{noreply, State}.

handle_info({timeout, _TRef, {ping, #jid{luser = LUser, lserver = LServer} = JID, Record}}, State) ->
    Key = ?lookup_key(LUser, LServer),
    case mnesia:dirty_read(component_lb, Key) of
        [Record] ->
            send_ping(State#state.host, JID, Record),
            Timers = add_timer(JID, Record, ?PING_INTERVAL, State#state.timers);
        NewRecord ->
            ?WARNING_MSG("Record changed before ping: ~p to ~p", [Record, NewRecord]),
            Timers = del_timer(JID, Record, State#state.timers)
    end,
    State1 = State#state{timers = Timers},
    {noreply, State1};
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
-spec start_ping(Node :: node(), JID :: jid:jid(), Record :: component_lb()) -> ok.
start_ping(Node, JID, Record) when JID#jid.lresource =:= <<>> ->
	?INFO_MSG("start_ping: ~p, ~p", [Node, JID]),
	gen_server:cast({?MODULE, Node}, {start_ping, JID, Record}).

-spec send_ping(Host::any, JID :: jid:jid(), Record :: component_lb()) -> mongoose_acc:t().
send_ping(Host, JID, Record) ->
    ?INFO_MSG("Sending ping disco to ~p", [JID]),
    IQ = #iq{type = get,
             sub_el = [#xmlel{name = <<"query">>,
                              attrs = [{<<"xmlns">>, ?NS_DISCO_INFO}]}]},
    Pid = self(),
    F = fun(_From, _To, Acc, Response) ->
                gen_server:cast(Pid, {iq_pong, JID, Record, Response}),
                Acc
        end,
    From = jid:make(<<"">>, Host, <<"">>),
    Acc = mongoose_acc:from_element(IQ, From, JID),
    ejabberd_local:route_iq(From, JID, Acc, IQ, F, ?PING_REQ_TIMEOUT).

-spec add_timer(JID :: jid:jid(), Record :: component_lb(),
                Interval :: non_neg_integer(), Timers :: timers()) -> timers().
add_timer(JID, Record, Interval, Timers) ->
    NewTimers = case maps:find(JID, Timers) of
                    {ok, {OldTRef, Record}} ->
                        cancel_timer(OldTRef),
                        maps:remove(JID, Timers);
                    {ok, {OldTRef, OldRecord}} ->
                        ?WARNING_MSG("Overwriting existing backend timer ~p with ~p; this is weird",
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
delete_record(#jid{luser = LUser, lserver = LServer} = JID, Record, State) ->
    Timers = del_timer(JID, Record, State#state.timers),
    case mnesia:transaction(fun () -> mnesia:delete_object(Record) end) of
        {atomic, _} -> ok;
        {aborted, Reason} -> ?WARNING_MSG("Error deleting ~p: ~p", [Record, Reason])
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

lookup_backend_transient(Backends, #jid{luser = LUser} = From) ->
	get_random_backend(Backends, LUser).

lookup_backend_persistent(Backends, #jid{luser = LUser, lserver = LServer} = To) ->
	Key = ?lookup_key(LUser, LServer),
	case mnesia:dirty_read(component_lb, Key) of
		[#component_lb{key = Key, backend = Domain, handler = Handler, node = Node}] ->
			?INFO_MSG("found backend in mnesia: ~p => ~p", [Key, {Domain, Handler}]),
			{Domain, Handler, Node};
		[] ->
			case get_random_backend(Backends, LUser) of
				{Domain, Handler, Node} ->
					write_record(Key, Domain, Handler, Node);
				notfound ->
					notfound
			end;
		Any ->
			?ERROR_MSG("Unexpected component_lb lookup result: ~p", [Any]),
			error
	end.

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
	case mnesia:transaction(F, ?TX_RETRIES) of
		{atomic, R} ->
			?INFO_MSG("inserted backend to mnesia: ~p => ~p", [Key, R]),
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
    {Module, Code} = dynamic_compile:from_string(Source),
    code:load_binary(Module, "mod_component_lb_dynamic.erl", Code),
    ok.

mod_component_lb_dynamic_src(Frontends) ->
    lists:flatten(
        ["-module(mod_component_lb_dynamic).
         -export([get_backends/1]).

         get_backends(Domain) ->
             ", io_lib:format("maps:find(Domain, ~p)", [Frontends]), ".\n"]).

-spec reload(State :: state()) -> ok.
reload(State) ->
    %% TODO: iterate instead of grabbing all records in one go
    Records = mnesia:dirty_select(
                component_lb,
                [{#component_lb{node = '$1', key = '$2', _ = '_'},
                  [{'==', '$1', node()}],
                  ['$_']}]),
    Acc = State,
    lists:foldl(fun(Record, State) ->
                        reload(Record, State)
                end, Acc, Records).

-spec reload(Record :: component_lb(), State :: state()) -> ok.
reload(#component_lb{key = {LUser, LServer}} = Record, #state{timers = Timers} = State) ->
    JID = jid:make(LUser, LServer, <<>>),
    case maps:find(JID, Timers) of
        {ok, {_TRef, Record}} ->
            Timers1 = Timers;
        _ ->
            Interval = rand:uniform(?PING_INTERVAL),
            Timers1 = add_timer(JID, Record, Interval, Timers)
    end,
    State#state{timers = Timers1}.
