defmodule Plug.Cowboy.Supervisor do
  @moduledoc false
  use Supervisor

  @spec child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    scheme = Keyword.fetch!(opts, :scheme)

    {plug, _plug_opts} =
      plug_tuple =
      case Keyword.fetch!(opts, :plug) do
        {_, _} = tuple -> tuple
        plug -> {plug, []}
      end

    ref = get_in(opts, [:options, :ref]) || Plug.Cowboy.build_ref(plug, scheme)

    opts =
      opts
      |> Keyword.put(:plug, plug_tuple)
      |> Keyword.put_new(:options, [])
      |> put_in([:options, :ref], ref)

    %{
      id: {ref, __MODULE__},
      start: {Plug.Cowboy.Supervisor, :start_link, [opts]},
      restart: :permanent,
      shutdown: :infinity,
      type: :supervisor,
      modules: [__MODULE__]
    }
  end

  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    children = [
      {Plug.Cowboy.Listener, opts},
      {Plug.Cowboy.Drainer, opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
