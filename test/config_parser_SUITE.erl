-module(config_parser_SUITE).
-compile([export_all]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-include("ejabberd_config.hrl").

-define(eq(Expected, Actual), ?assertEqual(Expected, Actual)).

all() ->
    [equivalence, miscellaneous, s2s, modules].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(jid),
    Config.

end_per_suite(_Config) ->
    ok.

equivalence(Config) ->
    CfgPath = ejabberd_helper:data(Config, "mongooseim-pgsql.cfg"),
    State1 = mongoose_config_parser_cfg:parse_file(CfgPath),
    Hosts1 = mongoose_config_parser:state_to_host_opts(State1),
    Opts1 = mongoose_config_parser:state_to_opts(State1),

    TOMLPath = ejabberd_helper:data(Config, "mongooseim-pgsql.toml"),
    State2 = mongoose_config_parser_toml:parse_file(TOMLPath),
    Hosts2 = mongoose_config_parser:state_to_host_opts(State2),
    Opts2 = mongoose_config_parser:state_to_opts(State2),
    ?eq(Hosts1, Hosts2),
    compare_unordered_lists(lists:filter(fun filter_config/1, Opts1), Opts2,
                            fun handle_config_option/2).

miscellaneous(Config) ->
    CfgPath = ejabberd_helper:data(Config, "miscellaneous.cfg"),
    State1 = mongoose_config_parser_cfg:parse_file(CfgPath),
    Hosts1 = mongoose_config_parser:state_to_host_opts(State1),
    Opts1 = mongoose_config_parser:state_to_opts(State1),

    TOMLPath = ejabberd_helper:data(Config, "miscellaneous.toml"),
    State2 = mongoose_config_parser_toml:parse_file(TOMLPath),
    Hosts2 = mongoose_config_parser:state_to_host_opts(State2),
    Opts2 = mongoose_config_parser:state_to_opts(State2),

    ?eq(Hosts1, Hosts2),
    compare_unordered_lists(lists:filter(fun filter_config/1, Opts1), Opts2,
                        fun handle_config_option/2).


s2s(Config) ->
    Cfg_Path = ejabberd_helper:data(Config, "s2s_only.cfg"),
    State1 = mongoose_config_parser_cfg:parse_file(Cfg_Path),
    Opts1 = mongoose_config_parser:state_to_opts(State1),

    TOML_path = ejabberd_helper:data(Config, "s2s_only.toml"),
    State2 = mongoose_config_parser_toml:parse_file(TOML_path),
    Opts2 = mongoose_config_parser:state_to_opts(State2),
        
    compare_unordered_lists(lists:filter(fun filter_config/1, Opts1), Opts2,
                            fun handle_config_option/2).

modules(Config) ->
    CfgPath = ejabberd_helper:data(Config, "modules.cfg"),
    State1 = mongoose_config_parser_cfg:parse_file(CfgPath),
    Hosts1 = mongoose_config_parser:state_to_host_opts(State1),
    Opts1 = mongoose_config_parser:state_to_opts(State1),

    TOMLPath = ejabberd_helper:data(Config, "modules.toml"),
    State2 = mongoose_config_parser_toml:parse_file(TOMLPath),
    Hosts2 = mongoose_config_parser:state_to_host_opts(State2),
    Opts2 = mongoose_config_parser:state_to_opts(State2),

    ?eq(Hosts1, Hosts2),
    compare_unordered_lists(lists:filter(fun filter_config/1, Opts1), Opts2,
                        fun handle_config_option/2).
filter_config(#config{key = required_files}) ->
    false; % not supported yet in TOML
filter_config(_) -> true.

handle_config_option(#config{key = K1, value = V1},
                     #config{key = K2, value = V2}) ->
    ?eq(K1, K2),
    compare_values(K1, V1, V2);
handle_config_option(#local_config{key = K1, value = V1},
                     #local_config{key = K2, value = V2}) ->
    ?eq(K1, K2),
    compare_values(K1, V1, V2);
handle_config_option(Opt1, Opt2) ->
    ?eq(Opt1, Opt2).

compare_values(listen, V1, V2) ->
    compare_unordered_lists(V1, V2, fun handle_listener/2);
compare_values({auth_opts, _}, V1, V2) ->
    compare_unordered_lists(V1, V2, fun handle_auth_opt/2);
compare_values(outgoing_pools, V1, V2) ->
    compare_unordered_lists(V1, V2, fun handle_conn_pool/2);
compare_values({modules, _}, V1, V2) ->
    compare_unordered_lists(V1, V2, fun handle_item_with_opts/2);
compare_values({services, _}, V1, V2) ->
    compare_unordered_lists(V1, V2, fun handle_item_with_opts/2);
compare_values({auth_method, _}, V1, V2) when is_atom(V1) ->
    ?eq([V1], V2);
compare_values({s2s_addr, _}, {_, _, _, _} = IP1, IP2) ->
    ?eq(inet:ntoa(IP1), IP2);
compare_values(services, V1, V2) ->
    MetricsOpts1 = proplists:get_value(service_mongoose_system_metrics, V1),
    MetricsOpts2 = proplists:get_value(service_mongoose_system_metrics, V2),
    compare_unordered_lists(MetricsOpts1, MetricsOpts2);
compare_values(K, V1, V2) ->
    ?eq({K, V1}, {K, V2}).

handle_listener({P1, M1, O1}, {P2, M2, O2}) ->
    ?eq(P1, P2),
    ?eq(M1, M2),
    compare_unordered_lists(O1, O2, fun handle_listener_option/2).

handle_listener_option({modules, M1}, {modules, M2}) ->
    compare_unordered_lists(M1, M2, fun handle_listener_module/2);
handle_listener_option({transport_options, O1}, {transport_options, O2}) ->
    compare_unordered_lists(O1, O2);
handle_listener_option(V1, V2) -> ?eq(V1, V2).

handle_listener_module({H1, P1, M1}, M2) ->
    handle_listener_module({H1, P1, M1, []}, M2);
handle_listener_module({H1, P1, M1, O1}, {H2, P2, M2, O2}) ->
    ?eq(H1, H2),
    ?eq(P1, P2),
    ?eq(M1, M2),
    compare_listener_module_options(M1, O1, O2).

compare_listener_module_options(mod_websockets,
                                [{ejabberd_service, S1}], [{ejabberd_service, S2}]) ->
    compare_unordered_lists(S1, S2);
compare_listener_module_options(_, O1, O2) ->
    ?eq(O1, O2).

handle_auth_opt({cyrsasl_external, M}, {cyrsasl_external, [M]}) -> ok;
handle_auth_opt(V1, V2) -> ?eq(V1, V2).

handle_item_with_opts({M1, O1}, {M2, O2}) ->
    ?eq(M1, M2),
    compare_unordered_lists(O1, O2).

handle_conn_pool({Type1, Scope1, Tag1, POpts1, COpts1},
                 {Type2, Scope2, Tag2, POpts2, COpts2}) ->
    ?eq(Type1, Type2),
    ?eq(Scope1, Scope2),
    ?eq(Tag1, Tag2),
    compare_unordered_lists(POpts1, POpts2),
    compare_unordered_lists(COpts1, COpts2, fun handle_conn_opt/2).

handle_conn_opt({server, {D1, H1, DB1, U1, P1, O1}},
                {server, {D2, H2, DB2, U2, P2, O2}}) ->
    ?eq(D1, D2),
    ?eq(H1, H2),
    ?eq(DB1, DB2),
    ?eq(U1, U2),
    ?eq(P1, P2),
    compare_unordered_lists(O1, O2, fun handle_db_server_opt/2);
handle_conn_opt(V1, V2) -> ?eq(V1, V2).

handle_db_server_opt({ssl_opts, O1}, {ssl_opts, O2}) ->
    compare_unordered_lists(O1, O2);
handle_db_server_opt(V1, V2) -> ?eq(V1, V2).

compare_unordered_lists(L1, L2) ->
    compare_unordered_lists(L1, L2, fun(V1, V2) -> ?eq(V1, V2) end).

compare_unordered_lists(L1, L2, F) ->
    SL1 = lists:sort(L1),
    SL2 = lists:sort(L2),
    compare_ordered_lists(SL1, SL2, F).

compare_ordered_lists([H1|T1], [H1|T2], F) ->
    compare_ordered_lists(T1, T2, F);
compare_ordered_lists([{backends, Backends}], [{backends, Backends2}], _) ->
    Sns = proplists:get_value(sns, Backends, []),
    Sns2 = proplists:get_value(sns, Backends2, []),
    Push = proplists:get_value(push, Backends, []),
    Push2 = proplists:get_value(push, Backends2, []),
    Http = proplists:get_value(http, Backends, []),
    Http2 = proplists:get_value(http, Backends2, []),
    compare_unordered_lists(Sns, Sns2),
    compare_unordered_lists(Push, Push2),
    compare_unordered_lists(Http, Http2);
compare_ordered_lists([{mod_event_pusher_rabbit, Opts}|T1], [{mod_event_pusher_rabbit, Opts2}|T2], F) ->
    Presence = proplists:get_value(presence_exchange, Opts, []),
    Presence2 = proplists:get_value(presence_exchange, Opts2, []),
    Chat = proplists:get_value(chat_msg_exchange, Opts, []),
    Chat2 = proplists:get_value(chat_msg_exchange, Opts2, []),
    Group = proplists:get_value(groupchat_msg_exchange, Opts, []),
    Group2 = proplists:get_value(groupchat_msg_exchange, Opts2, []),
    compare_unordered_lists(Presence, Presence2),
    compare_unordered_lists(Chat, Chat2),
    compare_unordered_lists(Group, Group2),
    compare_ordered_lists(T1, T2, F);
compare_ordered_lists([{mod_keystore, Opts}|T1], [{mod_keystore, Opts2}|T2], F) ->
    Keys1 = proplists:get_value(keys, Opts, []),
    Keys2 = proplists:get_value(keys, Opts2, []),
    compare_unordered_lists(Keys1, Keys2),
    compare_unordered_lists(lists:keydelete(keys, 1, Opts), lists:keydelete(keys, 1, Opts2)),
    compare_ordered_lists(T1, T2, F);
compare_ordered_lists([{Name, Opts} = H1|T1], [{Name, Opts2} = H2|T2], F) ->
    Names = [
        configs,
        s3,
        bounce,
        connections,
        tls_opts,
        mod_event_pusher,
        mod_event_pusher_sns, 
        mod_event_pusher_http,
        mod_event_pusher_push,
        mod_http_upload, 
        mod_inbox, 
        mod_global_distrib, 
        mod_jingle_sip,
        mod_mam_meta,
        mod_muc,
        default_room_options,
        mod_muc_log,
        mod_muc_light,
        config_schema,
        mod_ping,
        mod_pubsub,
        mod_push_service_mongoosepush,
        mod_register,
        mod_revproxy,
        routes,
        mod_stream_management,
        stale_h,
        muc, 
        pm
    ],
    case lists:member(Name, Names) of
        true ->
                compare_unordered_lists(Opts, Opts2),
                compare_ordered_lists(T1, T2, F);
        _ ->
            try F(H1, H2)
            catch C:R:S ->
                    ct:fail({C, R, S})
            end,
             compare_ordered_lists(T1, T2, F)
        end;
compare_ordered_lists([H1|T1], [H2|T2], F) when is_list(H1), is_list(H2)->
    compare_unordered_lists(H1, H2),
    compare_ordered_lists(T1, T2, F);
compare_ordered_lists([H1|T1], [H2|T2], F) ->
    try F(H1, H2)
    catch C:R:S ->
            ct:fail({C, R, S})
    end,
    compare_ordered_lists(T1, T2, F);
compare_ordered_lists([], [], _) ->
    ok.
