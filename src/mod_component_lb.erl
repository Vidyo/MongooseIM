-module(mod_component_lb).
-author('igor.slepchin@gmail.com').

-behavior(gen_server).
-behaviour(gen_mod).

-include("mongoose.hrl").
-include("mongoose_ns.hrl").
-include("jid.hrl").
-include("jlib.hrl").
-include("mod_component_lb.hrl").

%% API
-export([start_link/2, get_backends/1, get_frontend/1, start_ping/3]).

%% gen_mod callbacks
-export([start/2,
         stop/1]).

%% gen_server callbacks
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2,
         code_change/3]).

%% Hooks callbacks
-export([node_cleanup/2, unregister_subhost/2]).

-record(state, {lb = #{},
				backends = #{},
				timers = maps:new(),
				host}).

-define(PING_INTERVAL, 5000).
-define(PING_REQ_TIMEOUT, ?PING_INTERVAL div 2).
%% -define(PROCNAME, ejabberd_mod_component_lb).

%%====================================================================
%% API
%%====================================================================
start_link(Host, Opts) ->
    Proc = ?MODULE,
	?INFO_MSG("start_link: host ~p, proc ~p", [Host, Proc]),
    gen_server:start_link({local, Proc}, ?MODULE, [Host, Opts], []).

get_backends(Domain) ->
	mod_component_lb_dynamic:get_backends(Domain).

get_frontend(Domain) ->
	Proc = ?MODULE, %%gen_mod:get_module_proc(Host, ?PROCNAME),
	gen_server:call(Proc, {frontend, Domain}).

start_ping(Host, Node, JID) when JID#jid.lresource =:= <<>> ->
	?INFO_MSG("start_ping: ~p, ~p, ~p", [Host, Node, JID]),
	gen_server:cast({?MODULE, Node}, {start_ping, JID}).

%% stop_ping(Host, JID) ->
%%     gen_server:cast(?MODULE, {stop_ping, JID}).

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
    %% Pid = erlang:whereis(Proc),
    %% gen_server:call(Proc, stop),
    %% wait_for_process_to_stop(Pid),
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

handle_call({frontend, Domain}, _From, #state{backends = Backends} = State) ->
	%% ?DEBUG("frontends for ~p", [Domain]),
	{reply, maps:find(Domain, Backends), State}.
%% handle_call(stop, _From, State) ->
%% 	?INFO_MSG("stop"),
%% 	{stop, normal, ok, State}.

handle_cast({start_ping, JID}, State) ->
    Timers = add_timer(JID, ?PING_INTERVAL, State#state.timers),
    {noreply, State#state{timers = Timers}};
handle_cast({iq_pang, #jid{luser = LUser, lserver = LServer} = JID, timeout}, State) ->
	?INFO_MSG("backend ping timeout on ~p", [JID]),
    Timers = del_timer(JID, State#state.timers),
	Key = {LUser, LServer},
	{atomic, _} = mnesia:transaction(fun () -> mnesia:delete({component_lb, Key}) end),
    {noreply, State#state{timers = Timers}};
handle_cast({iq_pang, JID, Response}, State) ->
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
                gen_server:cast(Pid, {iq_pang, JID, Response}),
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

process_opts([{lb, LBOpts}|Opts], State) ->
	State1 = process_lb_opt(LBOpts, State),
	process_opts(Opts, State1);
process_opts([Opt|Opts], State) ->
	?ERROR_MSG("unknown opt: ~p", [Opt]),
	process_opts(Opts, State);
process_opts([], State) ->
	State.

process_lb_opt({LBDomain, Backends}, #state{lb = LBDomains} = State)
  when is_list(Backends) ->
	?INFO_MSG("lb opt: ~p => ~p", [LBDomain, Backends]),
    LBDomainBin = list_to_binary(LBDomain),
	BackendsBin = lists:map(fun erlang:list_to_binary/1, Backends),
	LBDomains1  = LBDomains#{LBDomainBin => BackendsBin},
	State1 = process_lb_backends(LBDomainBin, BackendsBin, State#state{lb = LBDomains1}),
	?INFO_MSG("lb opt state: ~p", [State1]),
	State1;
process_lb_opt(Opt, State) ->
	?ERROR_MSG("unknown lb opt: ~p", [Opt]),
	State.

process_lb_backends(LBDomain, [Backend|Backends], #state{backends = StateBackends} = State) ->
	StateBackends1 = StateBackends#{Backend => LBDomain},
	State1 = State#state{backends = StateBackends1},
	process_lb_backends(LBDomain, Backends, State1);
process_lb_backends(_LBDomain, [], State) ->
	State.

compile_frontends(Frontends) ->
    Source = mod_component_lb_dynamic_src(Frontends),
	?INFO_MSG("dynamic src: ~p", [Source]),
    {Module, Code} = dynamic_compile:from_string(Source),
    code:load_binary(Module, "mod_component_lb_dynamic.erl", Code),
    ok.

mod_component_lb_dynamic_src(Frontends) ->
    lists:flatten(
        ["-module(mod_component_lb_dynamic).
         -export([get_backends/1]).

         get_backends(Domain) ->
             ", io_lib:format("maps:find(Domain, ~p)", [Frontends]), ".\n"]).
