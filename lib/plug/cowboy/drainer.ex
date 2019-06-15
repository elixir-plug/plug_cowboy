defmodule Plug.Cowboy.Drainer do
  @moduledoc false
  use GenServer

  @spec child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    ref = Keyword.fetch!(opts, :ref)
    drain_timeout = Keyword.get(opts, :drain_timeout, 1_000)

    %{
      id: {ref, __MODULE__},
      start: {__MODULE__, :start_link, [{ref, drain_timeout}]},
      restart: :permanent,
      shutdown: :infinity,
      type: :worker,
      modules: [__MODULE__]
    }
  end

  @spec start_link({ref :: module(), drain_timeout :: non_neg_integer()}) :: GenServer.on_start()
  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  @spec init({ref :: module(), drain_timeout :: non_neg_integer()}) ::
          {:ok, {ref :: module(), drain_timeout :: non_neg_integer()}}
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @impl true
  def terminate(_reason, {ref, drain_timeout}) do
    Plug.Cowboy.drain(ref, drain_timeout: drain_timeout)
  end
end
