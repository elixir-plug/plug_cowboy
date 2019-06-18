defmodule Plug.CowboyTest do
  use ExUnit.Case, async: true

  import Plug.Cowboy
  import ExUnit.CaptureIO

  def init([]) do
    [foo: :bar]
  end

  handler = {:_, [], Plug.Cowboy.Handler, {Plug.CowboyTest, [foo: :bar]}}
  @dispatch [{:_, [], [handler]}]

  test "supports Elixir v1.5 child specs" do
    spec = {Plug.Cowboy, [scheme: :http, plug: __MODULE__, options: [port: 4040]]}

    assert %{
              id: {Plug.CowboyTest.HTTP, Plug.Cowboy.Supervisor},
              start: {Plug.Cowboy.Supervisor, :start_link, _},
              restart: :permanent,
              shutdown: :infinity,
              type: :supervisor,
              modules: [Plug.Cowboy.Supervisor]
            } = Supervisor.child_spec(spec, [])
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
             %{env: %{dispatch: @dispatch}, compress: true, timeout: 30_000}
           ] = args(:http, __MODULE__, [], port: 3000, compress: true, timeout: 30_000)

    assert [
             Plug.CowboyTest.HTTP,
             %{num_acceptors: 100, max_connections: 16_384, socket_opts: [port: 3000]},
             %{env: %{dispatch: @dispatch}, timeout: 30_000}
           ] = args(:http, __MODULE__, [], port: 3000, protocol_options: [timeout: 30_000])
  end

  test "builds args with num_acceptors option writes a deprecation" do
    output =
      capture_io(:stderr, fn ->
        assert [
                 Plug.CowboyTest.HTTP,
                 %{max_connections: 16_384, socket_opts: [port: 3000], num_acceptors: 5},
                 %{env: %{dispatch: @dispatch}}
               ] = args(:http, __MODULE__, [], port: 3000, compress: true, num_acceptors: 5)
      end)

    assert output =~ "using :num_acceptors in options is deprecated"
    assert output =~ "Please pass :num_acceptors"
  end

  test "build args using acceptors has a custom deprecation warning" do
    output =
      capture_io(:stderr, fn ->
        assert [
                 Plug.CowboyTest.HTTP,
                 %{max_connections: 16_384, socket_opts: [port: 3000], num_acceptors: 5},
                 %{env: %{dispatch: @dispatch}}
               ] = args(:http, __MODULE__, [], port: 3000, compress: true, acceptors: 5)
      end)

    assert output =~ "using :acceptors in options is deprecated"
    assert output =~ "Please pass :num_acceptors"
  end

  test "builds args with compress option" do
    assert [
             Plug.CowboyTest.HTTP,
             %{num_acceptors: 100, max_connections: 16_384, socket_opts: [port: 3000]},
             %{
               env: %{dispatch: @dispatch},
               stream_handlers: [:cowboy_compress_h, Plug.Cowboy.Stream]
             }
           ] = args(:http, __MODULE__, [], port: 3000, compress: true)
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
end
