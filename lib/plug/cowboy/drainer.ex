defmodule Plug.Cowboy.Drainer do
  use GenServer

  @spec child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    {opts, shutdown} = Keyword.pop(opts, :shutdown, 5_000)

    Supervisor.child_spec(
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]},
        type: :worker
      },
      shutdown: shutdown
    )
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, opts}
  end

  @doc false
  @impl true
  def terminate(_reason, opts) do
    opts
    |> Keyword.get(:refs)
    |> drain(Keyword.get(opts, :drain_check_interval, 1_000))
  end

  defp drain(nil, drain_check_interval) do
    :ranch.info()
    |> Enum.map(&elem(&1, 0))
    |> drain(drain_check_interval)
  end

  defp drain(refs, drain_check_interval) do
    refs
    |> Stream.each(&suspend/1)
    |> Enum.filter(&suspended?/1)
    |> Enum.each(&wait_for_connections(&1, drain_check_interval))
  end

  defp suspend(ref), do: :ranch.suspend_listener(ref)

  defp suspended?(ref), do: :ranch.get_status(ref) == :suspended

  defp wait_for_connections(ref, drain_check_interval) do
    :ranch.wait_for_connections(ref, :==, 0, drain_check_interval)
  end
end
