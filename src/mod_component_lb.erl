-module(mod_component_lb).
-author('igor.slepchin@gmail.com').

-behavior(gen_server).
-behaviour(gen_mod).

-include("mongoose.hrl").
-include("jid.hrl").

%% API
-export([start_link/2, get_backends/1, get_frontend/1]).

%% gen_mod callbacks
-export([start/2,
         stop/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2,
         code_change/3]).
%% -export([init/1, terminate/2, handle_call/3, handle_cast/2,
%%          handle_info/2, code_change/3]).

-record(state, {lb = #{},
				backends = #{}}).

-define(PROCNAME, ejabberd_mod_component_lb).

%%====================================================================
%% API
%%====================================================================
start_link(Host, Opts) ->
    Proc = ?MODULE, %%gen_mod:get_module_proc(Host, ?PROCNAME),
	?INFO_MSG("start_link: host ~p, proc ~p", [Host, Proc]),
    gen_server:start_link({local, Proc}, ?MODULE, [Host, Opts], []).

    %% Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
	%% ?INFO_MSG("start_link: host ~p, proc ~p", [Host, Proc]),
    %% gen_server:start_link({local, Proc}, ?MODULE, [Host, Opts], []).

get_backends(Domain) ->
	Proc = ?MODULE, %%gen_mod:get_module_proc(Host, ?PROCNAME),
	gen_server:call(Proc, {backends, Domain}).

get_frontend(Domain) ->
	Proc = ?MODULE, %%gen_mod:get_module_proc(Host, ?PROCNAME),
	gen_server:call(Proc, {frontend, Domain}).

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
	State = #state{},
	State1 = process_opts(Opts, State),
	?INFO_MSG("LB State: ~p", [State1]),
	{ok, State1}.

handle_call({backends, Domain}, _From, #state{lb = Frontends} = State) ->
	?INFO_MSG("backends for ~p in ~p", [Domain, Frontends]),
	{reply, maps:find(Domain, Frontends), State};
handle_call({frontend, Domain}, _From, #state{backends = Backends} = State) ->
	?INFO_MSG("frontends for ~p", [Domain]),
	{reply, maps:find(Domain, Backends), State}.
%% handle_call(stop, _From, State) ->
%% 	?INFO_MSG("stop"),
%% 	{stop, normal, ok, State}.

handle_cast(Request, State) ->
	?INFO_MSG("handle_cast: ~p, ~p", [Request, State]),
	{noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

route(From, To, Acc, Packet) ->
	case route_to(From, To, Acc, Packet) of
		{F, T, A, P} ->
			{F, T, A, P};
		_ ->
			case route_from(From, To, Acc, Packet) of
				{F, T, A, P} ->
					{F, T, A, P};
				_ ->
					{From, To, Acc, Packet}
			end
	end.

route_to(From, #jid{lserver=LServer, luser=LUser} = To, Acc, Packet) ->
	case catch gen_mod:get_module_opt(?MYNAME, ?MODULE, LServer) of
		[] ->
			ok;
		[H|T] ->
			LBServer = route_lb(LUser, [H|T]),
			To1 = To#jid{lserver = LBServer, server = LBServer},
			{From, To1, Acc, Packet};
		_ ->
			ok
	end.

route_from(#jid{lserver=LServer, luser = <<>>} = From, To, Acc, Packet) ->
	ok;
route_from(#jid{lserver=LServer, luser=LUser} = From, To, Acc, Packet) ->
	ok.

route_lb(LUser, LBDomains) ->
	F = fun(Domain) ->
				case ets:lookup(external_component_global, Domain) of
					[] -> false;
					[H|T] -> true
				end
		end,
	ActiveLBDomains = lists:filter(F, LBDomains),
	N = erlang:phash2(LUser, length(ActiveLBDomains)),
	lists:nth(N+1, ActiveLBDomains).

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
process_lb_backends(LBDomain, [], State) ->
	State.
