-module(ejabberd_loglevel_SUITE_helper).
-export([log/4]).

-include_lib("kernel/include/logger.hrl").

log(_, critical, Fmt, Args) -> ?LOG_CRITICAL(Fmt, Args);
log(_, error, Fmt, Args)    -> ?LOG_ERROR(Fmt, Args);
log(_, warning, Fmt, Args)  -> ?LOG_WARNING(Fmt, Args);
log(_, info, Fmt, Args)     -> ?LOG_INFO(Fmt, Args);
log(_, debug, Fmt, Args)    -> ?LOG_DEBUG(Fmt, Args).
