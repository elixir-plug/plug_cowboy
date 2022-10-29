defmodule WebSocketHandlerTest do
  use ExUnit.Case, async: true

  defmodule WebSocketHandler do
    @behaviour :cowboy_websocket

    # We never actually call this; it's just here to quell compiler warnings
    @impl true
    def init(req, state), do: {:cowboy_websocket, req, state}

    @impl true
    def websocket_init(_opts), do: {:ok, :init}

    @impl true
    def websocket_handle({:text, "state"}, state), do: {[{:text, inspect(state)}], state}

    def websocket_handle({:text, "whoami"}, state),
      do: {[{:text, :erlang.pid_to_list(self())}], state}

    @impl true
    def websocket_info(msg, state), do: {[{:text, inspect(msg)}], state}
  end

  @protocol_options [
    idle_timeout: 1000,
    request_timeout: 1000
  ]

  setup_all do
    {:ok, _} = Plug.Cowboy.http(__MODULE__, [], port: 8083, protocol_options: @protocol_options)
    on_exit(fn -> :ok = Plug.Cowboy.shutdown(__MODULE__.HTTP) end)
    {:ok, port: 8083}
  end

  @behaviour Plug

  @impl Plug
  def init(arg), do: arg

  @impl Plug
  def call(conn, _opts) do
    conn = Plug.Conn.fetch_query_params(conn)
    handler = conn.query_params["handler"] |> String.to_atom()
    Plug.Conn.upgrade_adapter(conn, :websocket, {handler, [], [timeout: 1000]})
  end

  test "websocket_init and websocket_handle are called", context do
    client = tcp_client(context)
    http1_handshake(client, WebSocketHandler)

    send_text_frame(client, "state")
    {:ok, result} = recv_text_frame(client)
    assert result == inspect(:init)
  end

  test "websocket_info is called", context do
    client = tcp_client(context)
    http1_handshake(client, WebSocketHandler)

    send_text_frame(client, "whoami")
    {:ok, pid} = recv_text_frame(client)
    pid = pid |> String.to_charlist() |> :erlang.list_to_pid()

    Process.send(pid, "hello info", [])

    {:ok, response} = recv_text_frame(client)
    assert response == inspect("hello info")
  end

  # Simple WebSocket client

  def tcp_client(context) do
    {:ok, socket} = :gen_tcp.connect('localhost', context[:port], active: false, mode: :binary)

    socket
  end

  def http1_handshake(client, module, params \\ []) do
    params = params |> Keyword.put(:handler, module)

    :gen_tcp.send(client, """
    GET /?#{URI.encode_query(params)} HTTP/1.1\r
    Host: server.example.com\r
    Upgrade: websocket\r
    Connection: Upgrade\r
    Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
    Sec-WebSocket-Version: 13\r
    \r
    """)

    {:ok, response} = :gen_tcp.recv(client, 234)

    [
      "HTTP/1.1 101 Switching Protocols",
      "cache-control: max-age=0, private, must-revalidate",
      "connection: Upgrade",
      "date: " <> _date,
      "sec-websocket-accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
      "server: Cowboy",
      "upgrade: websocket",
      "",
      ""
    ] = String.split(response, "\r\n")
  end

  defp recv_text_frame(client) do
    {:ok, 0x8, 0x1, body} = recv_frame(client)
    {:ok, body}
  end

  defp recv_frame(client) do
    {:ok, header} = :gen_tcp.recv(client, 2)
    <<flags::4, opcode::4, 0::1, length::7>> = header

    {:ok, data} =
      case length do
        0 ->
          {:ok, <<>>}

        126 ->
          {:ok, <<length::16>>} = :gen_tcp.recv(client, 2)
          :gen_tcp.recv(client, length)

        127 ->
          {:ok, <<length::64>>} = :gen_tcp.recv(client, 8)
          :gen_tcp.recv(client, length)

        length ->
          :gen_tcp.recv(client, length)
      end

    {:ok, flags, opcode, data}
  end

  defp send_text_frame(client, data, flags \\ 0x8) do
    send_frame(client, flags, 0x1, data)
  end

  defp send_frame(client, flags, opcode, data) do
    mask = :rand.uniform(1_000_000)
    masked_data = mask(data, mask)

    mask_flag_and_size =
      case byte_size(masked_data) do
        size when size <= 125 -> <<1::1, size::7>>
        size when size <= 65_535 -> <<1::1, 126::7, size::16>>
        size -> <<1::1, 127::7, size::64>>
      end

    :gen_tcp.send(client, [<<flags::4, opcode::4>>, mask_flag_and_size, <<mask::32>>, masked_data])
  end

  # Note that masking is an involution, so we don't need a separate unmask function
  defp mask(payload, mask, acc \\ <<>>)

  defp mask(payload, mask, acc) when is_integer(mask), do: mask(payload, <<mask::32>>, acc)

  defp mask(<<h::32, rest::binary>>, <<mask::32>>, acc) do
    mask(rest, mask, acc <> <<Bitwise.bxor(h, mask)::32>>)
  end

  defp mask(<<h::8, rest::binary>>, <<current::8, mask::24>>, acc) do
    mask(rest, <<mask::24, current::8>>, acc <> <<Bitwise.bxor(h, current)::8>>)
  end

  defp mask(<<>>, _mask, acc), do: acc
end
