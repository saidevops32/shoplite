
%% If the worker crashes (for example RabbitMQ drops), it is restarted here.
-module(order_worker_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 60},
    Child = #{id => order_worker, start => {order_worker, start_link, []}, restart => permanent},
    {ok, {SupFlags, [Child]}}.
