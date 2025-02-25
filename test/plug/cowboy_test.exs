defmodule Plug.CowboyTest do
  use ExUnit.Case, async: true

  import Plug.Cowboy

  def init([]) do
    [foo: :bar]
  end

  handler = {:_, [], Plug.Cowboy.Handler, {Plug.CowboyTest, [foo: :bar]}}
  @dispatch [{:_, [], [handler]}]

  test "supports Elixir child specs" do
    spec = {Plug.Cowboy, [scheme: :http, plug: __MODULE__, port: 4040]}

    ranch_listener_mod = ranch_listener_for_version()

    assert %{
             id: {^ranch_listener_mod, Plug.CowboyTest.HTTP},
             start: {^ranch_listener_mod, :start_link, _},
             type: :supervisor
           } = Supervisor.child_spec(spec, [])

    # For backwards compatibility:
    spec = {Plug.Cowboy, [scheme: :http, plug: __MODULE__, options: [port: 4040]]}

    assert %{
             id: {^ranch_listener_mod, Plug.CowboyTest.HTTP},
             start: {^ranch_listener_mod, :start_link, _},
             type: :supervisor
           } = Supervisor.child_spec(spec, [])

    spec =
      {Plug.Cowboy,
       [scheme: :http, plug: __MODULE__, parent: :key, options: [:inet6, port: 4040]]}

    assert %{
             id: {^ranch_listener_mod, Plug.CowboyTest.HTTP},
             start: {^ranch_listener_mod, :start_link, _},
             type: :supervisor
           } = Supervisor.child_spec(spec, [])
  end

  test "the h2 alpn settings are added when using https" do
    options = [
      port: 4040,
      password: "cowboy",
      keyfile: Path.expand("../fixtures/ssl/server_key_enc.pem", __DIR__),
      certfile: Path.expand("../fixtures/ssl/valid.pem", __DIR__)
    ]

    spec = {Plug.Cowboy, [scheme: :https, plug: __MODULE__] ++ options}

    ranch_listener_mod = ranch_listener_for_version()
    %{start: {^ranch_listener_mod, :start_link, opts}} = Supervisor.child_spec(spec, [])

    assert [
             Plug.CowboyTest.HTTPS,
             :ranch_ssl,
             %{socket_opts: socket_opts},
             :cowboy_tls,
             _proto_opts
           ] = opts

    assert Keyword.get(socket_opts, :alpn_preferred_protocols) == ["h2", "http/1.1"]
    assert Keyword.get(socket_opts, :next_protocols_advertised) == ["h2", "http/1.1"]
  end

  test "builds args for cowboy dispatch" do
    assert [
             Plug.CowboyTest.HTTP,
             %{num_acceptors: 100, socket_opts: [port: 4000], max_connections: 16_384},
             %{env: %{dispatch: @dispatch}}
           ] = args(:http, __MODULE__, [], [])
  end

  test "builds args with custom options" do
    assert [
             Plug.CowboyTest.HTTP,
             %{
               num_acceptors: 100,
               max_connections: 16_384,
               socket_opts: [port: 3000, other: true]
             },
             %{env: %{dispatch: @dispatch}}
           ] = args(:http, __MODULE__, [], port: 3000, other: true)
  end

  test "builds args with non 2-element tuple options" do
    assert [
             Plug.CowboyTest.HTTP,
             %{
               num_acceptors: 100,
               max_connections: 16_384,
               socket_opts: [:inet6, {:raw, 1, 2, 3}, port: 3000, other: true]
             },
             %{env: %{dispatch: @dispatch}}
           ] = args(:http, __MODULE__, [], [:inet6, {:raw, 1, 2, 3}, port: 3000, other: true])
  end

  test "builds args with protocol option" do
    assert [
             Plug.CowboyTest.HTTP,
             %{num_acceptors: 100, max_connections: 16_384, socket_opts: [port: 3000]},
             %{env: %{dispatch: @dispatch}, compress: true}
           ] = args(:http, __MODULE__, [], port: 3000, compress: true)

    assert [
             Plug.CowboyTest.HTTP,
             %{num_acceptors: 100, max_connections: 16_384, socket_opts: [port: 3000]},
             %{env: %{dispatch: @dispatch}, timeout: 30_000}
           ] = args(:http, __MODULE__, [], port: 3000, protocol_options: [timeout: 30_000])
  end

  test "builds args with compress option" do
    assert [
             Plug.CowboyTest.HTTP,
             %{num_acceptors: 100, max_connections: 16_384, socket_opts: [port: 3000]},
             %{
               env: %{dispatch: @dispatch},
               stream_handlers: [:cowboy_compress_h, :cowboy_telemetry_h, :cowboy_stream_h]
             }
           ] = args(:http, __MODULE__, [], port: 3000, compress: true)
  end

  test "builds args with net option" do
    assert [
             Plug.CowboyTest.HTTP,
             %{num_acceptors: 100, max_connections: 16_384, socket_opts: [:inet6, port: 3000]},
             %{
               env: %{dispatch: @dispatch},
               stream_handlers: [:cowboy_telemetry_h, :cowboy_stream_h]
             }
           ] = args(:http, __MODULE__, [], port: 3000, net: :inet6)
  end

  test "builds args with transport options" do
    assert [
             Plug.CowboyTest.HTTP,
             %{
               num_acceptors: 50,
               max_connections: 16_384,
               shutdown: :brutal_kill,
               socket_opts: [:inets, priority: 1, port: 3000]
             },
             %{
               env: %{dispatch: @dispatch}
             }
           ] =
             args(:http, __MODULE__, [],
               port: 3000,
               transport_options: [
                 shutdown: :brutal_kill,
                 num_acceptors: 50,
                 socket_opts: [:inets, priority: 1]
               ]
             )
  end

  test "builds args with compress option fails if stream_handlers are set" do
    assert_raise(RuntimeError, ~r/set both compress and stream_handlers/, fn ->
      args(:http, __MODULE__, [], port: 3000, compress: true, stream_handlers: [:cowboy_stream_h])
    end)
  end

  test "builds args with single-atom protocol option" do
    assert [
             Plug.CowboyTest.HTTP,
             %{num_acceptors: 100, max_connections: 16_384, socket_opts: [:inet6, port: 3000]},
             %{env: %{dispatch: @dispatch}}
           ] = args(:http, __MODULE__, [], [:inet6, port: 3000])
  end

  test "builds child specs" do
    ranch_listener_mod = ranch_listener_for_version()

    assert %{
             id: {^ranch_listener_mod, Plug.CowboyTest.HTTP},
             start: {^ranch_listener_mod, :start_link, _},
             type: :supervisor
           } = child_spec(scheme: :http, plug: __MODULE__, options: [])
  end

  defp ranch_listener_for_version() do
    case Version.parse!("#{Application.spec(:ranch, :vsn)}") |> Version.compare("2.2.0") do
      :lt -> :ranch_listener_sup
      _ -> :ranch_embedded_sup
    end
  end
end
