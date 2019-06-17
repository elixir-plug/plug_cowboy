defmodule Plug.Cowboy.Listener do
  @moduledoc false

  @spec child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    scheme = Keyword.fetch!(opts, :scheme)
    {plug, plug_opts} = Keyword.fetch!(opts, :plug)

    cowboy_opts =
      opts
      |> Keyword.get(:options, [])
      |> Keyword.delete(:drain_timeout)
      |> Keyword.delete(:drain_check_interval)

    cowboy_args = Plug.Cowboy.args(scheme, plug, plug_opts, cowboy_opts)
    [ref, transport_opts, proto_opts] = cowboy_args

    {ranch_module, cowboy_protocol, transport_opts} =
      case scheme do
        :http ->
          {:ranch_tcp, :cowboy_clear, transport_opts}

        :https ->
          %{socket_opts: socket_opts} = transport_opts

          socket_opts =
            socket_opts
            |> Keyword.put_new(:next_protocols_advertised, ["h2", "http/1.1"])
            |> Keyword.put_new(:alpn_preferred_protocols, ["h2", "http/1.1"])

          {:ranch_ssl, :cowboy_tls, %{transport_opts | socket_opts: socket_opts}}
      end

    {id, start, restart, shutdown, type, modules} =
      :ranch.child_spec(ref, ranch_module, transport_opts, cowboy_protocol, proto_opts)

    %{id: id, start: start, restart: restart, shutdown: shutdown, type: type, modules: modules}
  end
end
