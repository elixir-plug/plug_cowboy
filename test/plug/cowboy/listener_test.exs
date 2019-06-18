defmodule Plug.Cowboy.ListenerTest do
  use ExUnit.Case, async: true
  import Plug.Cowboy.Listener

  def init([]) do
    [foo: :bar]
  end

  test "builds child specs" do
    assert %{
             id: {:ranch_listener_sup, Plug.Cowboy.ListenerTest.HTTP},
             modules: [:ranch_listener_sup],
             start: {:ranch_listener_sup, :start_link, _},
             restart: :permanent,
             shutdown: :infinity,
             type: :supervisor
           } = child_spec(scheme: :http, plug: {__MODULE__, []}, options: [])
  end

  test "the h2 alpn settings are added when using https" do
    options = [
      port: 4040,
      password: "cowboy",
      keyfile: Path.expand("../../fixtures/ssl/server_key_enc.pem", __DIR__),
      certfile: Path.expand("../../fixtures/ssl/valid.pem", __DIR__)
    ]

    child_spec = child_spec(scheme: :https, plug: {__MODULE__, []}, options: options)
    %{start: {:ranch_listener_sup, :start_link, opts}} = child_spec

    assert [
             Plug.Cowboy.ListenerTest.HTTPS,
             :ranch_ssl,
             %{socket_opts: socket_opts},
             :cowboy_tls,
             _proto_opts
           ] = opts

    assert Keyword.get(socket_opts, :alpn_preferred_protocols) == ["h2", "http/1.1"]
    assert Keyword.get(socket_opts, :next_protocols_advertised) == ["h2", "http/1.1"]
  end
end
