%%%
%%% Copyright 2011, Boundary
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%

%%%-------------------------------------------------------------------
%%% File:      folsom_ets.erl
%%% @author    joe williams <j@boundary.com>
%%% @doc
%%% @end
%%%------------------------------------------------------------------

-module(folsom_ets).

%% API
-export([
         add_handler/2,
         add_handler/3,
         add_handler/4,
         add_handler/5,
         delete_handler/1,
         handler_exists/1,
         notify/1,
         notify/2,
         notify/3,
         notify_existing_metric/3,
         get_handlers/0,
         get_handlers_info/0,
         get_info/1,
         get_values/1,
         get_history_values/2
        ]).

-record(metric, {
          tags = [],
          type,
          history_size
         }).

-include("folsom.hrl").

%%%===================================================================
%%% API
%%%===================================================================

add_handler(Type, Name) ->
    maybe_add_handler(Type, Name, handler_exists(Name)).

add_handler(Type, Name, SampleSize) ->
    maybe_add_handler(Type, Name, SampleSize, handler_exists(Name)).

add_handler(Type, Name, SampleType, SampleSize) ->
    maybe_add_handler(Type, Name, SampleType, SampleSize, handler_exists(Name)).

add_handler(Type, Name, SampleType, SampleSize, Alpha) ->
    maybe_add_handler(Type, Name, SampleType, SampleSize, Alpha, handler_exists(Name)).

delete_handler(Name) ->
    {_, Info} = get_info(Name),
    case proplists:get_value(type, Info) of
        history ->
            ok = delete_history(Name);
        _ ->
            true = ets:delete(?FOLSOM_TABLE, Name)
    end,
    ok.

handler_exists(Name) ->
    ets:member(?FOLSOM_TABLE, Name).

%% old tuple style notifications
notify({Name, Event}) ->
    notify(Name, Event).

%% notify/2, checks metric type and makes sure metric exists
%% before notifying, returning error if not
notify(Name, Event) ->
    case handler_exists(Name) of
        true ->
            {_, Info} = get_info(Name),
            Type = proplists:get_value(type, Info),
            notify(Name, Event, Type, true);
        false ->
            {error, Name, nonexistant_metric}
    end.

%% notify/3, makes sure metric exist, if not creates metric
notify(Name, Event, Type) ->
    case handler_exists(Name) of
        true ->
            notify(Name, Event, Type, true);
        false ->
            notify(Name, Event, Type, false)
    end.

%% assumes metric already exists, bypasses above checks
notify_existing_metric(Name, Event, Type) ->
    notify(Name, Event, Type, true).

get_handlers() ->
    proplists:get_keys(ets:tab2list(?FOLSOM_TABLE)).

get_handlers_info() ->
    Handlers = get_handlers(),
    [get_info(Id) || Id <- Handlers].

get_info(Name) ->
    [{_, #metric{type = Type}}] = ets:lookup(?FOLSOM_TABLE, Name),
    {Name, [{type, Type}]}.

get_values(Name) ->
    {_, Info} = get_info(Name),
    get_values(Name, proplists:get_value(type, Info)).

get_values(Name, counter) ->
    folsom_metrics_counter:get_value(Name);
get_values(Name, gauge) ->
    folsom_metrics_gauge:get_value(Name);
get_values(Name, histogram) ->
    folsom_metrics_histogram:get_values(Name);
get_values(Name, history) ->
    folsom_metrics_history:get_events(Name);
get_values(Name, meter) ->
    folsom_metrics_meter:get_values(Name);
get_values(_, Type) ->
    {error, Type, unsupported_metric_type}.

get_history_values(Name, Count) ->
    folsom_metrics_history:get_events(Name, Count).

%%%===================================================================
%%% Internal functions
%%%===================================================================

maybe_add_handler(counter, Name, false) ->
    true = folsom_metrics_counter:new(Name),
    true = ets:insert(?FOLSOM_TABLE, {Name, #metric{type = counter}}),
    ok;
maybe_add_handler(gauge, Name, false) ->
    true = folsom_metrics_gauge:new(Name),
    true = ets:insert(?FOLSOM_TABLE, {Name, #metric{type = gauge}}),
    ok;
maybe_add_handler(histogram, Name, false) ->
    true = folsom_metrics_histogram:new(Name),
    true = ets:insert(?FOLSOM_TABLE, {Name, #metric{type = histogram}}),
    ok;
maybe_add_handler(history, Name, false) ->
    ok = folsom_metrics_history:new(Name),
    true = ets:insert(?FOLSOM_TABLE, {Name, #metric{type = history, history_size = ?DEFAULT_SIZE}}),
    ok;
maybe_add_handler(meter, Name, false) ->
    {ok, _} = timer:apply_interval(?DEFAULT_INTERVAL, folsom_metrics_meter, tick, Name),
    true = folsom_metrics_meter:new(Name),
    true = ets:insert(?FOLSOM_TABLE, {Name, #metric{type = meter}}),
    ok;
maybe_add_handler(Type, _, false) ->
    {error, Type, unsupported_metric_type};
maybe_add_handler(_, Name, true) ->
    {error, Name, metric_already_exists}.

maybe_add_handler(histogram, Name, SampleType, false) ->
    true = folsom_metrics_histogram:new(Name, SampleType),
    true = ets:insert(?FOLSOM_TABLE, {Name, #metric{type = histogram}}),
    ok;
maybe_add_handler(history, Name, SampleSize, false) ->
    ok = folsom_metrics_history:new(Name),
    true = ets:insert(?FOLSOM_TABLE, {Name, #metric{type = history, history_size = SampleSize}}),
    ok;
maybe_add_handler(Type, _, _, false) ->
    {error, Type, unsupported_metric_type};
maybe_add_handler(_, Name, _, true) ->
    {error, Name, metric_already_exists}.

maybe_add_handler(histogram, Name, SampleType, SampleSize, false) ->
    true = folsom_metrics_histogram:new(Name, SampleType, SampleSize),
    true = ets:insert(?FOLSOM_TABLE, {Name, #metric{type = histogram}}),
    ok;
maybe_add_handler(Type, _, _, _, false) ->
    {error, Type, unsupported_metric_type};
maybe_add_handler(_, Name, _, _, true) ->
    {error, Name, metric_already_exists}.

maybe_add_handler(histogram, Name, SampleType, SampleSize, Alpha, false) ->
    true = folsom_metrics_histogram:new(Name, SampleType, SampleSize, Alpha),
    true = ets:insert(?FOLSOM_TABLE, {Name, #metric{type = histogram}}),
    ok;
maybe_add_handler(Type, _, _, _, _, false) ->
    {error, Type, unsupported_metric_type};
maybe_add_handler(_, Name, _, _, _, true) ->
    {error, Name, metric_already_exists}.

delete_history(Name) when is_binary(Name)->
    true = ets:delete(folsom_utils:to_atom(Name)),
    true = ets:delete(?FOLSOM_TABLE, Name),
    ok;
delete_history(Name) when is_atom(Name) ->
    true = ets:delete(Name),
    true = ets:delete(?FOLSOM_TABLE, Name),
    ok;
delete_history(Name) ->
    {error, Name, invalid_history_name}.

notify(Name, {inc, Value}, counter, true) ->
    folsom_metrics_counter:inc(Name, Value),
    ok;
notify(Name, {inc, Value}, counter, false) ->
    add_handler(counter, Name),
    folsom_metrics_counter:inc(Name, Value),
    ok;
notify(Name, {dec, Value}, counter, true) ->
    folsom_metrics_counter:dec(Name, Value),
    ok;
notify(Name, {dec, Value}, counter, false) ->
    add_handler(counter, Name),
    folsom_metrics_counter:dec(Name, Value),
    ok;
notify(Name, Value, gauge, true) ->
    folsom_metrics_gauge:update(Name, Value),
    ok;
notify(Name, Value, gauge, false) ->
    add_handler(gauge, Name),
    folsom_metrics_gauge:update(Name, Value),
    ok;
notify(Name, Value, histogram, true) ->
    folsom_metrics_histogram:update(Name, Value),
    ok;
notify(Name, Value, histogram, false) ->
    add_handler(histogram, Name),
    folsom_metrics_histogram:update(Name, Value),
    ok;
notify(Name, Value, history, true) ->
    [{_, #metric{history_size = HistorySize}}] = ets:lookup(?FOLSOM_TABLE, Name),
    folsom_metrics_history:update(Name, HistorySize, Value),
    ok;
notify(Name, Value, history, false) ->
    add_handler(history, Name),
    [{_, #metric{history_size = HistorySize}}] = ets:lookup(?FOLSOM_TABLE, Name),
    folsom_metrics_history:update(Name, HistorySize, Value),
    ok;
notify(Name, Value, meter, true) ->
    folsom_metrics_meter:mark(Name, Value),
    ok;
notify(Name, Value, meter, false) ->
    add_handler(meter, Name),
    folsom_metrics_meter:mark(Name, Value),
    ok;
notify(_, _, Type, _) ->
    {error, Type, unsupported_metric_type}.
