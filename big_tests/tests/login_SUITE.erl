%%==============================================================================
%% Copyright 2010 Erlang Solutions Ltd.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================

-module(login_SUITE).
-compile(export_all).

-include_lib("escalus/include/escalus.hrl").
-include_lib("escalus/include/escalus_xmlns.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-include_lib("exml/include/exml.hrl").

-import(distributed_helper, [mim/0,
                             require_rpc_nodes/1,
                             rpc/4]).

%%--------------------------------------------------------------------
%% Suite configuration
%%--------------------------------------------------------------------

-define(REGISTRATION_TIMEOUT, 2).  %% seconds

all() ->
    [
     {group, login},
     {group, login_digest},
     {group, login_scram},
     {group, login_scram_store_plain},
     {group, login_specific_scram},
     {group, messages}
    ].

groups() ->
    G = [{login, [parallel], all_tests()},
         {login_digest, [sequence], digest_tests()},
         {login_scram, [parallel], scram_tests()},
         {login_scram_store_plain, [parallel], scram_tests()},
         {login_specific_scram, [sequence], configure_specific_scram_test()},
         {messages, [sequence], [messages_story, message_zlib_limit]}],
    ct_helper:repeat_all_until_all_ok(G).

scram_tests() ->
    [log_one,
     log_one_scram_sha1,
     log_one_scram_sha224,
     log_one_scram_sha256,
     log_one_scram_sha384,
     log_one_scram_sha512].

configure_specific_scram_test() ->
    [configure_sha1_log_with_sha1,
     configure_sha224_log_with_sha224,
     configure_sha256_log_with_sha256,
     configure_sha384_log_with_sha384,
     configure_sha512_log_with_sha512,
     configure_sha1_fail_log_with_sha224,
     configure_sha224_fail_log_with_sha256,
     configure_sha256_fail_log_with_sha384,
     configure_sha384_fail_log_with_sha512,
     configure_sha512_fail_log_with_sha1].

all_tests() ->
    [log_one,
     log_non_existent_plain,
     log_one_scram_sha1,
     log_non_existent_scram,
     blocked_user
    ].

digest_tests() ->
    [log_one_digest,
     log_non_existent_digest].

suite() ->
    require_rpc_nodes([mim]) ++ escalus:suite().

%%--------------------------------------------------------------------
%% Init & teardown
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    escalus:init_per_suite(Config).

end_per_suite(Config) ->
    escalus_fresh:clean(),
    escalus:end_per_suite(Config).

init_per_group(GroupName, Config) when
      GroupName == login_scram; GroupName == login_scram_store_plain ->
    case are_sasl_scram_modules_supported() of
        false ->
            {skip, "scram password type not supported"};
        true ->
            config_password_format(GroupName),
            Config2 = escalus:create_users(Config, escalus:get_users([alice, bob])),
            assert_password_format(GroupName, Config2)
    end;
init_per_group(login_specific_scram, Config) ->
    case are_sasl_scram_modules_supported() of
        false ->
            {skip, "scram password type not supported"};
        true ->
            escalus:create_users(Config, escalus:get_users([alice, bob]))
    end;
init_per_group(_GroupName, Config) ->
    escalus:create_users(Config, escalus:get_users([alice, bob])).

end_per_group(GroupName, Config) when
    GroupName == login_scram; GroupName == login_specific_scram ->
    set_store_password(plain),
    escalus:delete_users(Config, escalus:get_users([alice, bob]));
end_per_group(_GroupName, Config) ->
    escalus:delete_users(Config, escalus:get_users([alice, bob])).

init_per_testcase(CaseName, Config) when
      CaseName =:= log_one_digest; CaseName =:= log_non_existent_digest ->
    case mongoose_helper:supports_sasl_module(cyrsasl_digest) of
        false ->
            {skip, "digest password type not supported"};
        true ->
            Config1 = configure_digest(Config),
            escalus:init_per_testcase(CaseName, Config1)
    end;
init_per_testcase(CaseName, Config) when
      CaseName =:= log_one_scram_sha1; CaseName =:= log_non_existent_scram ->
    case mongoose_helper:supports_sasl_module(cyrsasl_scram_sha1) of
        false ->
            {skip, "scram password type not supported"};
        true ->
            escalus:init_per_testcase(CaseName, Config)
    end;
init_per_testcase(message_zlib_limit, Config) ->
    Listeners = [Listener
                 || {Listener, _, _} <- rpc(mim(), ejabberd_config, get_local_option, [listen])],
    [{_U, Props}] = escalus_users:get_users([hacker]),
    Port = proplists:get_value(port, Props),
    case lists:keymember(Port, 1, Listeners) of
        true ->
            escalus:create_users(Config, escalus:get_users([hacker])),
            escalus:init_per_testcase(message_zlib_limit, Config);
        false ->
            {skip, port_not_configured_on_server}
    end;
init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(message_zlib_limit, Config) ->
    escalus:delete_users(Config, escalus:get_users([hacker]));
end_per_testcase(CaseName, Config) when
    CaseName =:= log_one_digest; CaseName =:= log_non_existent_digest ->
    restore_config(Config),
    escalus:end_per_testcase(CaseName, Config);
end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).

%%--------------------------------------------------------------------
%% Message tests
%%--------------------------------------------------------------------

log_one(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->

        escalus_client:send(Alice, escalus_stanza:chat_to(Alice, <<"Hi!">>)),
        escalus:assert(is_chat_message, [<<"Hi!">>], escalus_client:wait_for_stanza(Alice))

        end).

log_one_digest(Config) ->
    log_one([{escalus_auth_method, <<"DIGEST-MD5">>} | Config]).

log_one_scram_sha1(Config) ->
    log_one([{escalus_auth_method, <<"SCRAM-SHA-1">>} | Config]).

log_one_scram_sha224(Config) ->
    log_one([{escalus_auth_method, <<"SCRAM-SHA-224">>} | Config]).

log_one_scram_sha256(Config) ->
    log_one([{escalus_auth_method, <<"SCRAM-SHA-256">>} | Config]).

 log_one_scram_sha384(Config) ->
    log_one([{escalus_auth_method, <<"SCRAM-SHA-384">>} | Config]).

log_one_scram_sha512(Config) ->
    log_one([{escalus_auth_method, <<"SCRAM-SHA-512">>} | Config]).

configure_sha1_log_with_sha1(Config) ->
        configure_and_log_scram(Config, sha, <<"SCRAM-SHA-1">>).

configure_sha224_log_with_sha224(Config) ->
    configure_and_log_scram(Config, sha224, <<"SCRAM-SHA-224">>).

configure_sha256_log_with_sha256(Config) ->
    configure_and_log_scram(Config, sha256, <<"SCRAM-SHA-256">>).

configure_sha384_log_with_sha384(Config) ->
    configure_and_log_scram(Config, sha384, <<"SCRAM-SHA-384">>).

configure_sha512_log_with_sha512(Config) ->
    configure_and_log_scram(Config, sha512, <<"SCRAM-SHA-512">>).

configure_sha1_fail_log_with_sha224(Config) ->
    configure_and_fail_log_scram(Config, sha, <<"SCRAM-SHA-224">>).

configure_sha224_fail_log_with_sha256(Config) ->
    configure_and_fail_log_scram(Config, sha224, <<"SCRAM-SHA-256">>).

configure_sha256_fail_log_with_sha384(Config) ->
    configure_and_fail_log_scram(Config, sha256, <<"SCRAM-SHA-384">>).

configure_sha384_fail_log_with_sha512(Config) ->
    configure_and_fail_log_scram(Config, sha384, <<"SCRAM-SHA-512">>).

configure_sha512_fail_log_with_sha1(Config) ->
    configure_and_fail_log_scram(Config, sha512, <<"SCRAM-SHA-1">>).

log_non_existent_plain(Config) ->
    {auth_failed, _, Xmlel} = log_non_existent(Config),
    #xmlel{name = <<"failure">>} = Xmlel,
    #xmlel{} = exml_query:subelement(Xmlel, <<"not-authorized">>).

log_non_existent_digest(Config) ->
    R = log_non_existent([{escalus_auth_method, <<"DIGEST-MD5">>} | Config]),
    {expected_challenge, _, _} = R.

log_non_existent_scram(Config) ->
    R = log_non_existent([{escalus_auth_method, <<"SCRAM-SHA-1">>} | Config]),
    {expected_challenge, _, _} = R.

log_non_existent(Config) ->
    [{kate, UserSpec}] = escalus_users:get_users([kate]),
    {error, {connection_step_failed, _, R}} = escalus_client:start(Config, UserSpec, <<"res">>),
    R.

blocked_user(_Config) ->
    [{_, Spec}] = escalus_users:get_users([alice]),
    set_acl_for_blocking(Spec),
    try
        {ok, _Alice, _Spec2, _Features} = escalus_connection:start(Spec),
        ct:fail("Alice authenticated but shouldn't")
    catch
        error:{assertion_failed, assert, is_iq_result, Stanza, _Bin} ->
            <<"cancel">> = exml_query:path(Stanza, [{element, <<"error">>}, {attr, <<"type">>}])
    after
        unset_acl_for_blocking(Spec)
    end,
    ok.

messages_story(Config) ->
    escalus:story(Config, [{alice, 1}, {bob, 1}], fun(Alice, Bob) ->

        % Alice sends a message to Bob
        escalus_client:send(Alice, escalus_stanza:chat_to(Bob, <<"Hi!">>)),

        % Bob gets the message
        escalus_assert:is_chat_message(<<"Hi!">>, escalus_client:wait_for_stanza(Bob))

    end).

message_zlib_limit(Config) ->
    escalus:story(Config, [{alice, 1}], fun(Alice) ->
        [{_, Spec}] = escalus_users:get_users([hacker]),
        {ok, Hacker, _Features} = escalus_connection:start(Spec),

        ManySpaces = [ 32 || _N <- lists:seq(1, 10*1024) ],

        escalus:send(Hacker, escalus_stanza:chat_to(Alice, ManySpaces)),

        escalus:assert(is_stream_error, [<<"policy-violation">>, <<"child element too big">>],
                       escalus:wait_for_stanza(Hacker)),
        escalus:assert(is_stream_end, escalus:wait_for_stanza(Hacker))

    end).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

configure_digest(Config) ->
    Config1 = ejabberd_node_utils:init(Config),
    ejabberd_node_utils:backup_config_file(Config1),
    ejabberd_node_utils:modify_config_file([{sasl_mechanisms, "{sasl_mechanisms, [cyrsasl_digest]}."}], Config1),
    ejabberd_node_utils:restart_application(mongooseim),
    Config1.

restore_config(Config) ->
    ejabberd_node_utils:restore_config_file(Config),
    ejabberd_node_utils:restart_application(mongooseim).

set_store_password(Type) ->
    XMPPDomain = escalus_ejabberd:unify_str_arg(
                   ct:get_config({hosts, mim, domain})),
    AuthOpts = rpc(mim(), ejabberd_config, get_local_option, [{auth_opts, XMPPDomain}]),
    NewAuthOpts = lists:keystore(password_format, 1, AuthOpts, {password_format, Type}),
    rpc(mim(), ejabberd_config, add_local_option, [{auth_opts, XMPPDomain}, NewAuthOpts]).

config_password_format(login_scram) ->
    set_store_password(scram);
config_password_format(_) ->
    set_store_password(plain).

assert_password_format(GroupName, Config) ->
    Users = proplists:get_value(escalus_users, Config),
    [verify_format(GroupName, User) || User <- Users],
    Config.

verify_format(GroupName, {_User, Props}) ->
    Username = escalus_utils:jid_to_lower(proplists:get_value(username, Props)),
    Server = proplists:get_value(server, Props),
    Password = proplists:get_value(password, Props),

    SPassword = rpc(mim(), ejabberd_auth, get_password, [Username, Server]),
    do_verify_format(GroupName, Password, SPassword).


do_verify_format(GroupName, _P, #{salt   := _S, iteration_count := _IC,
                                  sha    := #{stored_key := _, server_key := _},
                                  sha224 := #{stored_key := _, server_key := _},
                                  sha256 := #{stored_key := _, server_key := _},
                                  sha384 := #{stored_key := _, server_key := _},
                                  sha512 := #{stored_key := _, server_key := _}}) when
                 GroupName == login_scram orelse GroupName == scram ->
    true;
do_verify_format({scram, Sha}, _Password, ScramMap = #{salt := _S, iteration_count := _IC}) ->
   maps:is_key(Sha, ScramMap);
do_verify_format(login_scram, _Password, SPassword) ->
    %% returned password is a tuple containing scram data
    {_, _, _, _} = SPassword;
do_verify_format(_, Password, SPassword) ->
    Password = SPassword.

set_acl_for_blocking(Spec) ->
    modify_acl_for_blocking(add, Spec).

unset_acl_for_blocking(Spec) ->
    modify_acl_for_blocking(delete, Spec).

modify_acl_for_blocking(Method, Spec) ->
    ct:print("Spec: ~p", [Spec]),
    Domain = ct:get_config({hosts, mim, domain}),
    User = proplists:get_value(username, Spec),
    Lower = escalus_utils:jid_to_lower(User),
    rpc(mim(), acl, Method, [Domain, blocked, {user, Lower}]).

configure_and_log_scram(Config, Sha, Mech) ->
    set_store_password({scram, [Sha]}),
    assert_password_format({scram, Sha}, Config),
    log_one([{escalus_auth_method, Mech} | Config]).

configure_and_fail_log_scram(Config, Sha, Mech) ->
    set_store_password({scram, [Sha]}),
    assert_password_format({scram, Sha}, Config),
    {expected_challenge, _, _} = fail_log_one([{escalus_auth_method, Mech} | Config]).

fail_log_one(Config) ->
    [{alice, UserSpec}] = escalus_users:get_users([alice]),
    {error, {connection_step_failed, _, R}} = escalus_client:start(Config, UserSpec, <<"res">>),
    R.

are_sasl_scram_modules_supported() ->
    ScramModules = [cyrsasl_scram_sha1, cyrsasl_scram_sha224, cyrsasl_scram_sha256,
                    cyrsasl_scram_sha384, cyrsasl_scram_sha512],
    IsSupported = [mongoose_helper:supports_sasl_module(Module) || Module <- ScramModules],
    [true, true, true, true, true] == IsSupported.
