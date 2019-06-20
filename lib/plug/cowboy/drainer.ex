defmodule Plug.Cowboy.Drainer do
  @moduledoc """
  TODO: description
  """
  use GenServer

  @doc """
  TODO: description

  ## Options

    * `:id` - The ID for the process.
      Defaults to `Plug.Cowboy.Drainer`.

    * `:shutdown` - How long to wait for connections to drain.
      Defaults to 5000ms.

    * `:refs` - The cowboy listener refs to drain connections for.
      Defaults to all cowboy listeners.

    * `:drain_check_interval` - How frequently to check if a listener's
      connections have been drained.
      Defaults to 1000ms.
  """
  @spec child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    {spec_opts, opts} = Keyword.split(opts, [:id, :shutdown])

    Supervisor.child_spec(
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]},
        type: :worker
      },
      spec_opts
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
