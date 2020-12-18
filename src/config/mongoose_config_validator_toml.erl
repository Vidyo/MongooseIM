-module(mongoose_config_validator_toml).

-export([validate/2,
         validate/3,
         validate_section/2,
         validate_list/2]).

-include("mongoose.hrl").
-include("mongoose_config_spec.hrl").
-include_lib("jid/include/jid.hrl").

-define(HOST, 'HOST').

-spec validate(mongoose_config_parser_toml:path(),
               mongoose_config_parser_toml:option() | mongoose_config_parser_toml:config_list()) ->
          any().
validate(Path, [F]) when is_function(F, 1) ->
    validate(Path, F(?HOST));

%% Modules
validate([<<"ack_freq">>, <<"mod_stream_management">>, <<"modules">>|_],
         [{ack_freq, V}]) ->
    validate_positive_integer_or_atom(V, never);
validate([<<"buffer_max">>, <<"mod_stream_management">>, <<"modules">>|_],
         [{buffer_max, V}]) ->
    validate_positive_integer_or_infinity_or_atom(V, no_buffer);
validate([<<"resume_timeout">>, <<"mod_stream_management">>, <<"modules">>|_],
         [{resume_timeout, V}]) ->
    validate_positive_integer(V);
validate([<<"enabled">>, <<"stale_h">>, <<"mod_stream_management">>, <<"modules">>|_],
         [{enabled, V}]) ->
    validate_boolean(V);
validate([<<"geriatric">>, <<"stale_h">>, <<"mod_stream_management">>, <<"modules">>|_],
         [{stale_h_geriatric, V}]) ->
    validate_positive_integer(V);
validate([<<"repeat_after">>, <<"stale_h">>, <<"mod_stream_management">>, <<"modules">>|_],
         [{stale_h_repeat_after, V}]) ->
    validate_positive_integer(V);
validate([<<"ldap_auth_check">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_auth_check, V}]) ->
    validate_boolean(V);
validate([<<"ldap_base">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_base, V}]) ->
    validate_string(V);
validate([<<"ldap_deref">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_deref, V}]) ->
    validate_enum(V, [never,always,finding,searching]);
validate([<<"ldap_filter">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_filter, V}]) ->
    validate_string(V);
validate([<<"ldap_gfilter">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_gfilter, V}]) ->
    validate_string(V);
validate([<<"ldap_group_cache_size">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_group_cache_size, V}]) ->
    validate_non_negative_integer(V);
validate([<<"ldap_group_cache_validity">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_group_cache_validity, V}]) ->
    validate_non_negative_integer(V);
validate([<<"ldap_groupattr">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_groupattr, V}]) ->
    validate_string(V);
validate([<<"ldap_groupdesc">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_groupdesc, V}]) ->
    validate_string(V);
validate([<<"ldap_memberattr">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_memberattr, V}]) ->
    validate_string(V);
validate([<<"ldap_memberattr_format">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_memberattr_format, V}]) ->
    validate_string(V);
validate([<<"ldap_memberattr_format_re">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_memberattr_format_re, V}]) ->
    validate_string(V);
validate([<<"ldap_pool_tag">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_pool_tag, V}]) ->
    validate_pool_name(V);
validate([<<"ldap_rfilter">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_rfilter, V}]) ->
    validate_string(V);
validate([<<"ldap_ufilter">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_ufilter, V}]) ->
    validate_string(V);
validate([<<"ldap_user_cache_size">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_user_cache_size, V}]) ->
    validate_non_negative_integer(V);
validate([<<"ldap_user_cache_validity">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_user_cache_validity, V}]) ->
    validate_non_negative_integer(V);
validate([<<"ldap_userdesc">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_userdesc, V}]) ->
    validate_string(V);
validate([<<"ldap_useruid">>, <<"mod_shared_roster_ldap">>, <<"modules">>|_],
         [{ldap_useruid, V}]) ->
    validate_string(V);
validate([<<"iqdisc">>, <<"mod_version">>, <<"modules">>|_],
         [{iqdisc, V}]) ->
    validate_iqdisc(V);
validate([<<"os_info">>, <<"mod_version">>, <<"modules">>|_],
         [{os_info, V}]) ->
    validate_boolean(V);
validate([<<"access">>, <<"mod_register">>, <<"modules">>|_],
         [{access, V}]) ->
    validate_non_empty_atom(V);
validate([item, <<"ip_access">>, <<"mod_register">>, <<"modules">>|_],
         [V]) ->
    validate_ip_access(V);
validate([<<"iqdisc">>, <<"mod_register">>, <<"modules">>|_],
         [{iqdisc, V}]) ->
    validate_iqdisc(V);
validate([<<"password_strength">>, <<"mod_register">>, <<"modules">>|_],
         [{password_strength, V}]) ->
    validate_non_negative_integer(V);
validate([item, <<"registration_watchers">>, <<"mod_register">>, <<"modules">>|_],
         [V]) ->
    validate_jid(V);
validate([<<"body">>, <<"welcome_message">>, <<"mod_register">>, <<"modules">>|_],
         [{body, V}]) ->
    validate_string(V);
validate([<<"subject">>, <<"welcome_message">>, <<"mod_register">>, <<"modules">>|_],
         [{subject, V}]) ->
    validate_string(V);
validate([<<"backend">>, <<"mod_last">>, <<"modules">>|_],
         [{backend, V}]) ->
    validate_backend(mod_last, V);
validate([<<"iqdisc">>, <<"mod_last">>, <<"modules">>|_],
         [{iqdisc, V}]) ->
    validate_iqdisc(V);
validate([<<"bucket_type">>, <<"riak">>, <<"mod_last">>, <<"modules">>|_],
         [{bucket_type, V}]) ->
    validate_non_empty_binary(V);
validate([<<"iqdisc">>, <<"mod_time">>, <<"modules">>|_],
         [{iqdisc, V}]) ->
    validate_iqdisc(V);
validate([item, <<"routes">>, <<"mod_revproxy">>, <<"modules">>|_],
         [V]) ->
    validate_revproxy_route(V);
validate([<<"iqdisc">>, <<"mod_sic">>, <<"modules">>|_],
         [{iqdisc, V}]) ->
    validate_iqdisc(V);
validate([<<"backend">>, <<"mod_roster">>, <<"modules">>|_],
         [{backend, V}]) ->
    validate_backend(mod_roster, V);
validate([<<"iqdisc">>, <<"mod_roster">>, <<"modules">>|_],
         [{iqdisc, V}]) ->
    validate_iqdisc(V);
validate([<<"bucket_type">>, <<"riak">>, <<"mod_roster">>, <<"modules">>|_],
         [{bucket_type, V}]) ->
    validate_non_empty_binary(V);
validate([<<"version_bucket_type">>, <<"riak">>, <<"mod_roster">>, <<"modules">>|_],
         [{version_bucket_type, V}]) ->
    validate_non_empty_binary(V);
validate([<<"store_current_id">>, <<"mod_roster">>, <<"modules">>|_],
         [{store_current_id, V}]) ->
    validate_boolean(V);
validate([<<"versioning">>, <<"mod_roster">>, <<"modules">>|_],
         [{versioning, V}]) ->
    validate_boolean(V);
validate([<<"backend">>, <<"mod_vcard">>, <<"modules">>|_],
         [{backend, V}]) ->
    validate_backend(mod_vcard, V);
validate([<<"host">>, <<"mod_vcard">>, <<"modules">>|_],
         [{host, V}]) ->
    validate_domain_template(V);
validate([<<"iqdisc">>, <<"mod_vcard">>, <<"modules">>|_],
         [{iqdisc, V}]) ->
    validate_iqdisc(V);
validate([<<"ldap_base">>, <<"mod_vcard">>, <<"modules">>|_],
         [{ldap_base, V}]) ->
    validate_string(V);
validate([item, <<"ldap_binary_search_fields">>, <<"mod_vcard">>, <<"modules">>|_],
         [V]) ->
    validate_non_empty_binary(V);
validate([<<"ldap_deref">>, <<"mod_vcard">>, <<"modules">>|_],
         [{ldap_deref, V}]) ->
    validate_enum(V, [never,always,finding,searching]);
validate([<<"ldap_filter">>, <<"mod_vcard">>, <<"modules">>|_],
         [{ldap_filter, V}]) ->
    validate_string(V);
validate([<<"ldap_pool_tag">>, <<"mod_vcard">>, <<"modules">>|_],
         [{ldap_pool_tag, V}]) ->
    validate_pool_name(V);
validate([item, <<"ldap_search_fields">>, <<"mod_vcard">>, <<"modules">>|_],
         [V]) ->
    validate_ldap_search_field(V);
validate([<<"ldap_search_operator">>, <<"mod_vcard">>, <<"modules">>|_],
         [{ldap_search_operator, V}]) ->
    validate_enum(V, ['or','and']);
validate([item, <<"ldap_search_reported">>, <<"mod_vcard">>, <<"modules">>|_],
         [V]) ->
    validate_ldap_search_reported(V);
validate([item, <<"ldap_uids">>, <<"mod_vcard">>, <<"modules">>|_],
         [V]) ->
    validate_ldap_uids(V);
validate([item, <<"ldap_vcard_map">>, <<"mod_vcard">>, <<"modules">>|_],
         [V]) ->
    validate_ldap_vcard_map(V);
validate([<<"matches">>, <<"mod_vcard">>, <<"modules">>|_],
         [{matches, V}]) ->
    validate_non_negative_integer_or_infinity(V);
validate([<<"bucket_type">>, <<"riak">>, <<"mod_vcard">>, <<"modules">>|_],
         [{bucket_type, V}]) ->
    validate_non_empty_binary(V);
validate([<<"search_index">>, <<"riak">>, <<"mod_vcard">>, <<"modules">>|_],
         [{search_index, V}]) ->
    validate_non_empty_binary(V);
validate([<<"search">>, <<"mod_vcard">>, <<"modules">>|_],
         [{search, V}]) ->
    validate_boolean(V);
validate(_Path, _Value) ->
    ok.

validate(V, binary, domain) -> validate_binary_domain(V);
validate(V, binary, non_empty) -> validate_non_empty_binary(V);
validate(V, binary, {module, Prefix}) ->
    validate_module(list_to_atom(atom_to_list(Prefix) ++ "_" ++ binary_to_list(V)));
validate(V, integer, non_negative) -> validate_non_negative_integer(V);
validate(V, integer, positive) -> validate_positive_integer(V);
validate(V, integer, port) -> validate_port(V);
validate(V, int_or_infinity, non_negative) -> validate_non_negative_integer_or_infinity(V);
validate(V, int_or_infinity, positive) -> validate_positive_integer_or_infinity(V);
validate(V, string, url) -> validate_url(V);
validate(V, string, domain) -> validate_domain(V);
validate(V, string, domain_template) -> validate_domain_template(V);
validate(V, string, ip_address) -> validate_ip_address(V);
validate(V, string, network_address) -> validate_network_address(V);
validate(V, string, filename) -> validate_filename(V);
validate(V, string, non_empty) -> validate_non_empty_string(V);
validate(V, string, dirname) -> validate_dirname(V);
validate(V, atom, module) -> validate_module(V);
validate(V, atom, {module, Prefix}) ->
    validate_module(list_to_atom(atom_to_list(Prefix) ++ "_" ++ atom_to_list(V)));
validate(V, atom, loglevel) -> validate_loglevel(V);
validate(V, atom, pool_name) -> validate_non_empty_atom(V);
validate(V, atom, shaper) -> validate_non_empty_atom(V);
validate(V, atom, access_rule) -> validate_non_empty_atom(V);
validate(V, atom, non_empty) -> validate_non_empty_atom(V);
validate(V, _, {enum, Values}) -> validate_enum(V, Values);
validate(_V, _, any) -> ok.

validate_list([_|_], non_empty) -> ok;
validate_list(L = [_|_], unique_non_empty) -> validate_unique_items(L);
validate_list(L, unique) -> validate_unique_items(L);
validate_list(L, any) when is_list(L) -> ok.

validate_section([_|_], non_empty) -> ok;
validate_section(L, any) when is_list(L) -> ok.

%% validators

validate_loglevel(Level) ->
    mongoose_logs:loglevel_keyword_to_number(Level).

validate_non_empty_binary(Value) when is_binary(Value), Value =/= <<>> -> ok.

validate_unique_items(Items) ->
    L = sets:size(sets:from_list(Items)),
    L = length(Items).

validate_boolean(Value) when is_boolean(Value) -> ok.

validate_module(Mod) ->
    case code:ensure_loaded(Mod) of
        {module, _} ->
            ok;
        Other ->
            error(#{what => module_not_found, module => Mod, reason => Other})
    end.

validate_positive_integer(Value) when is_integer(Value), Value > 0 -> ok.

validate_non_negative_integer(Value) when is_integer(Value), Value >= 0 -> ok.

validate_non_negative_integer_or_infinity(Value) when is_integer(Value), Value >= 0 -> ok;
validate_non_negative_integer_or_infinity(infinity) -> ok.

validate_positive_integer_or_infinity(Value) when is_integer(Value), Value > 0 -> ok;
validate_positive_integer_or_infinity(infinity) -> ok.

validate_positive_integer_or_atom(Value, Atom) when is_atom(Value), Value == Atom -> ok;
validate_positive_integer_or_atom(Value, _) when is_integer(Value), Value > 0 -> ok.

validate_positive_integer_or_infinity_or_atom(Value, _) when is_integer(Value), Value > 0 -> ok;
validate_positive_integer_or_infinity_or_atom(infinity, _) -> ok;
validate_positive_integer_or_infinity_or_atom(Value, Atom) when is_atom(Value), Value == Atom -> ok.

validate_enum(Value, Values) ->
    case lists:member(Value, Values) of
        true ->
            ok;
        false ->
            error(#{what => validate_enum_failed,
                    value => Value,
                    allowed_values => Values})
    end.

validate_ip_address(Value) ->
    {ok, _} = inet:parse_address(Value).

validate_port(Value) when is_integer(Value), Value >= 0, Value =< 65535 -> ok.

validate_non_empty_atom(Value) when is_atom(Value), Value =/= '' -> ok.

validate_non_empty_string(Value) when is_list(Value), Value =/= "" -> ok.

validate_jid(Jid) ->
    case jid:from_binary(Jid) of
        #jid{} ->
            ok;
        _ ->
            error(#{what => validate_jid_failed, value => Jid})
    end.

validate_iqdisc(no_queue) -> ok;
validate_iqdisc(one_queue) -> ok;
validate_iqdisc(parallel) -> ok;
validate_iqdisc({queues, N}) when is_integer(N), N > 0 -> ok.

validate_ip_access({Access, IPMask}) ->
    validate_enum(Access, [allow, deny]),
    validate_ip_mask_string(IPMask).

validate_backend(Mod, Backend) ->
    validate_module(backend_module:backend_module(Mod, Backend)).

validate_domain(Domain) when is_list(Domain) ->
    #jid{luser = <<>>, lresource = <<>>} = jid:from_binary(list_to_binary(Domain)),
    validate_domain_res(Domain).

validate_domain_res(Domain) ->
    case inet_res:gethostbyname(Domain) of
        {ok, _} ->
            ok;
        {error,formerr} ->
            error(#{what => cfg_validate_domain_failed,
                    reason => formerr, text => <<"Invalid domain name">>,
                    domain => Domain});
        {error,Reason} -> %% timeout, nxdomain
            ?LOG_WARNING(#{what => cfg_validate_domain,
                           reason => Reason, domain => Domain,
                           text => <<"Couldn't resolve domain. "
                  "It could cause issues with production installations">>}),
            ignore
    end.

validate_binary_domain(Domain) when is_binary(Domain) ->
    #jid{luser = <<>>, lresource = <<>>} = jid:from_binary(Domain),
    validate_domain_res(binary_to_list(Domain)).

validate_domain_template(Domain) ->
    validate_binary_domain(gen_mod:make_subhost(Domain, <<"example.com">>)).

validate_url(Url) ->
    validate_non_empty_string(Url).

validate_string(Value) ->
    is_binary(unicode:characters_to_binary(Value)).

validate_ip_mask_string(IPMaskString) ->
    validate_non_empty_string(IPMaskString),
    {ok, IPMask} = mongoose_lib:parse_ip_netmask(IPMaskString),
    validate_ip_mask(IPMask).

validate_ip_mask({IP, Mask}) ->
    validate_string(inet:ntoa(IP)),
    case IP of
        {_,_,_,_} ->
            validate_ipv4_mask(Mask);
        _ ->
            validate_ipv6_mask(Mask)
    end.

validate_ipv4_mask(Mask) ->
    validate_range(Mask, 0, 32).

validate_ipv6_mask(Mask) ->
    validate_range(Mask, 0, 128).

validate_network_address(Value) ->
    ?LOG_DEBUG(#{what => validate_network_address,
                 value => Value}),
    validate_oneof(Value, [fun validate_domain/1, fun validate_ip_address/1]).

validate_oneof(Value, Funs) ->
    Results = [safe_call_validator(F, Value) || F <- Funs],
    case lists:any(fun(R) -> R =:= ok end, Results) of
        true ->
            ok;
        false ->
            error(#{what => validate_oneof_failed,
                    validation_results => Results})
    end.

safe_call_validator(F, Value) ->
    try
        F(Value),
        ok
    catch error:Reason:Stacktrace ->
              #{reason => Reason, stacktrace => Stacktrace}
    end.

validate_range(Value, Min, Max) when Value >= Min, Value =< Max ->
    ok.

validate_filename(Filename) ->
    case file:read_file_info(Filename) of
        {ok, _} ->
            ok;
        Reason ->
            error(#{what => invalid_filename, filename => Filename, reason => Reason})
    end.

validate_dirname(Dirname) ->
    case file:list_dir(Dirname) of
        {ok, _} ->
            ok;
        Reason ->
            error(#{what => invalid_dirname, dirname => Dirname, reason => Reason})
    end.

validate_revproxy_route({Host, Path, Method, Upstream}) ->
    validate_non_empty_string(Host),
    validate_string(Path),
    validate_string(Method),
    validate_non_empty_string(Upstream);
validate_revproxy_route({Host, Path, Upstream}) ->
    validate_non_empty_string(Host),
    validate_string(Path),
    validate_non_empty_string(Upstream).

validate_ldap_vcard_map({VCardField, LDAPPattern, LDAPFields}) ->
    validate_non_empty_binary(VCardField),
    validate_non_empty_binary(LDAPPattern),
    lists:foreach(fun validate_non_empty_binary/1, LDAPFields).

validate_ldap_search_field({SearchField, LDAPField}) ->
    validate_non_empty_binary(SearchField),
    validate_non_empty_binary(LDAPField).

validate_ldap_search_reported({SearchField, VCardField}) ->
    validate_non_empty_binary(SearchField),
    validate_non_empty_binary(VCardField).

validate_ldap_uids({Attribute, Format}) ->
    validate_non_empty_string(Attribute),
    validate_non_empty_string(Format);
validate_ldap_uids(Attribute) ->
    validate_non_empty_string(Attribute).

validate_pool_name(V) ->
    validate_non_empty_atom(V).
