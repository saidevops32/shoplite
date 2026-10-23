%% Takes "order.created" messages, pretends to charge the card, and publishes "order.processed".
-module(order_worker).
-behaviour(gen_server).
-include_lib("amqp_client/include/amqp_client.hrl").

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(EXCHANGE, <<"shop.events">>).
-define(QUEUE, <<"worker.orders">>).

-record(state, {conn, chan}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    case connect(40) of
        {ok, Conn} ->
            erlang:monitor(process, Conn),

            {ok, Chan} = amqp_connection:open_channel(Conn),
            amqp_channel:call(Chan, #'exchange.declare'{exchange = ?EXCHANGE, type = <<"topic">>, durable = true}),
            amqp_channel:call(Chan, #'queue.declare'{queue = ?QUEUE, durable = true}),
            amqp_channel:call(Chan, #'queue.bind'{queue = ?QUEUE, exchange = ?EXCHANGE, routing_key = <<"order.created">>}),
            amqp_channel:call(Chan, #'basic.qos'{prefetch_count = 10}),
            amqp_channel:subscribe(Chan, #'basic.consume'{queue = ?QUEUE}, self()),
            logger:notice("Order worker connected to RabbitMQ"),
            {ok, #state{conn = Conn, chan = Chan}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(_Req, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State) -> {noreply, State}.

handle_info(#'basic.consume_ok'{}, State) -> {noreply, State};

handle_info({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}},
            #state{chan = Chan} = State) ->
    try
        Order = jsx:decode(Payload, [return_maps]),
        OrderId = maps:get(<<"orderId">>, Order),
        UserId = maps:get(<<"userId">>, Order),
        Cents = maps:get(<<"totalCents">>, Order),
        logger:notice("Processing order ~p for user ~p (~p cents)", [OrderId, UserId, Cents]),
        timer:sleep(2000),
        {Status, Reason} = charge(Cents),
        Result = jsx:encode(#{<<"orderId">> => OrderId,
                              <<"userId">> => UserId,
                              <<"status">> => Status,
                              <<"reason">> => Reason}),
        amqp_channel:cast(Chan,

            #'basic.publish'{exchange = ?EXCHANGE, routing_key = <<"order.processed">>},
            #amqp_msg{props = #'P_basic'{delivery_mode = 2, content_type = <<"application/json">>},
                      payload = Result})
    catch
        Class:Err -> logger:error("Bad order message: ~p:~p", [Class, Err])
    end,
    amqp_channel:cast(Chan, #'basic.ack'{delivery_tag = Tag}),
    {noreply, State};

%% RabbitMQ connection died: crash on purpose, the supervisor restarts us.
handle_info({'DOWN', _Ref, process, _Pid, Reason}, State) ->
    {stop, {rabbitmq_down, Reason}, State};
handle_info(#'basic.cancel'{}, State) -> {stop, normal, State};
handle_info(_Other, State) -> {noreply, State}.

terminate(_Reason, #state{conn = Conn}) -> catch amqp_connection:close(Conn), ok.

%% The "payment": anything above 5000.00 is declined.
charge(Cents) when is_integer(Cents), Cents > 500000 -> {<<"FAILED">>, <<"Amount is over the card limit">>};
charge(Cents) when is_integer(Cents), Cents > 0 -> {<<"PAID">>, <<>>};
charge(_) -> {<<"FAILED">>, <<"Invalid amount">>}.

connect(0) -> {error, rabbitmq_unreachable};
connect(Retries) ->
    Params = #amqp_params_network{
        host = env("RABBITMQ_HOST", "localhost"),
        port = list_to_integer(env("RABBITMQ_PORT", "5672")),
        username = list_to_binary(env("RABBITMQ_USER", "guest")),
        password = list_to_binary(env("RABBITMQ_PASS", "guest"))},
    case amqp_connection:start(Params) of
        {ok, Conn} -> {ok, Conn};
        {error, _} -> logger:notice("RabbitMQ not ready, retrying"), timer:sleep(3000), connect(Retries - 1)

    end.

env(Name, Default) -> case os:getenv(Name) of false -> Default; V -> V end.
