-module(cowboy_telemetry_h).
-behavior(cowboy_stream).

-export([init/3]).
-export([data/4]).
-export([info/3]).
-export([terminate/3]).
-export([early_error/5]).

init(StreamID, Req, Opts) ->
  SystemTime = erlang:system_time(),
  StartTime = erlang:monotonic_time(),
  telemetry:execute(
    [cowboy, request, start],
    #{system_time => SystemTime},
    #{stream_id => StreamID, req => Req}
  ),
  {Commands, Next} = cowboy_stream:init(StreamID, Req, Opts),
  {Commands, [Next | StartTime]}.

data(StreamID, IsFin, Data, [Next0 | StartTime]) ->
  {Commands, Next} = cowboy_stream:data(StreamID, IsFin, Data, Next0),
  {Commands, [Next | StartTime]}.

info(StreamID, Info, [Next0 | StartTime]) ->
  EndTime = erlang:monotonic_time(),
  case Info of
    {response, _, _, _} = Response ->
      telemetry:execute(
        [cowboy, request, stop],
        #{duration => EndTime - StartTime},
        #{stream_id => StreamID, response => Response}
      );
    {'EXIT', _, Reason} ->
      telemetry:execute(
        [cowboy, request, exception],
        #{duration => EndTime - StartTime},
        #{stream_id => StreamID, kind => exit, reason => Reason}
      );
    _ ->
      ignore
  end,
  {Commands, Next} = cowboy_stream:info(StreamID, Info, Next0),
  {Commands, [Next | StartTime]}.

terminate(StreamID, Reason, [Next | _]) ->
  cowboy_stream:terminate(StreamID, Reason, Next).

early_error(StreamID, Reason, PartialReq, Resp0, Opts) ->
  SystemTime = erlang:system_time(),
  Resp = cowboy_stream:early_error(StreamID, Reason, PartialReq, Resp0, Opts),
  telemetry:execute(
    [cowboy, request, early_error],
    #{system_time => SystemTime},
    #{stream_id => StreamID, reason => Reason, partial_req => PartialReq, response => Resp}
  ),
  Resp.
