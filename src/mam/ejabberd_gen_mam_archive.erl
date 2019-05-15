-module(ejabberd_gen_mam_archive).

-callback archive_size(Size :: integer(), Host :: jid:server(),
                       ArchiveID :: mod_mam:archive_id(), ArchiveJID :: jid:jid())
                      -> integer().

-callback archive_message(_Result, jid:server(),
                          MessID :: mod_mam:message_id(), ArchiveID :: mod_mam:archive_id(),
                          LocJID :: jid:jid(), RemJID :: jid:jid(),
                          SrcJID :: jid:jid(), Dir :: atom(), Packet :: any()) ->
    ok | {error, timeout}.

-callback lookup_messages(Result :: any(), Host :: jid:server(),
                          Params :: map()) -> Result when
      Result :: {ok, mod_mam:lookup_result()} | {error, 'policy-violation'}.

-callback remove_archive(Acc :: map(), Host :: jid:server(),
    ArchiveID :: mod_mam:archive_id(), ArchiveJID :: jid:jid()) -> map().

-type purge_single_message_result() :: ok | {error, 'not-allowed' | 'not-found' | term()}.

-type mam_gdpr_data() :: [{MessageID::bitstring(), Message::bitstring()}].


-callback get_mam_pm_gdpr_data(jid:user(), jid:server()) -> {ok, mam_gdpr_data()}.

-callback get_mam_muc_gdpr_data(jid:user(), jid:server()) -> {ok, mod_mam:messages()}.

-optional_callbacks([get_mam_pm_gdpr_data/2, get_mam_muc_gdpr_data/2]).
