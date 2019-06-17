defmodule Plug.Cowboy.Drainer do
  @moduledoc false
  use GenServer

  @type state :: {ref :: GenServer.name(), interval :: non_neg_integer}

  @spec child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    ref = get_in(opts, [:options, :ref])
    drain_timeout = get_in(opts, [:options, :drain_timeout]) || 5_000
    interval = get_in(opts, [:options, :drain_check_interval]) || 1_000

    %{
      id: {ref, __MODULE__},
      start: {__MODULE__, :start_link, [{ref, interval}]},
      restart: :permanent,
      shutdown: drain_timeout,
      type: :worker,
      modules: [__MODULE__]
    }
  end

  @spec start_link(state) :: GenServer.on_start()
  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  @spec init(state) :: {:ok, state}
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @impl true
  @spec terminate(reason :: term, state) :: term()
  def terminate(_reason, {ref, interval}) do
    Plug.Cowboy.drain(ref, drain_check_interval: interval)
  end
end
