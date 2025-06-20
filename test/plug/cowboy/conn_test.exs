defmodule Plug.Cowboy.ConnTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Plug.Conn
  import Plug.Conn

  ## Cowboy2 setup for testing
  #
  # We use hackney to perform an HTTP request against the cowboy/plug running
  # on port 8003. Plug then uses Kernel.apply/3 to dispatch based on the first
  # element of the URI's path.
  #
  # e.g. `assert {204, _, _} = request :get, "/build/foo/bar"` will perform a
  # GET http://127.0.0.1:8003/build/foo/bar and Plug will call build/1.

  @client_ssl_opts [
    verify: :verify_peer,
    keyfile: Path.expand("../../fixtures/ssl/client_key.pem", __DIR__),
    certfile: Path.expand("../../fixtures/ssl/client.pem", __DIR__),
    cacertfile: Path.expand("../../fixtures/ssl/ca_and_chain.pem", __DIR__)
  ]

  @protocol_options [
    idle_timeout: 1000,
    request_timeout: 1000
  ]

  @https_options [
    port: 8004,
    password: "cowboy",
    verify: :verify_peer,
    keyfile: Path.expand("../../fixtures/ssl/server_key_enc.pem", __DIR__),
    certfile: Path.expand("../../fixtures/ssl/valid.pem", __DIR__),
    cacertfile: Path.expand("../../fixtures/ssl/ca_and_chain.pem", __DIR__),
    protocol_options: @protocol_options
  ]

  setup_all do
    {:ok, _} = Plug.Cowboy.http(__MODULE__, [], port: 8003, protocol_options: @protocol_options)
    {:ok, _} = Plug.Cowboy.https(__MODULE__, [], @https_options)

    on_exit(fn ->
      :ok = Plug.Cowboy.shutdown(__MODULE__.HTTP)
      :ok = Plug.Cowboy.shutdown(__MODULE__.HTTPS)
    end)

    :ok
  end

  @already_sent {:plug_conn, :sent}

  def init(opts) do
    opts
  end

  def call(conn, []) do
    # Assert we never have a lingering @already_sent entry in the inbox
    refute_received @already_sent

    function = String.to_atom(List.first(conn.path_info) || "root")
    apply(__MODULE__, function, [conn])
  rescue
    exception ->
      receive do
        {:plug_conn, :sent} ->
          :erlang.raise(:error, exception, __STACKTRACE__)
      after
        0 ->
          send_resp(
            conn,
            500,
            Exception.message(exception) <>
              "\n" <> Exception.format_stacktrace(__STACKTRACE__)
          )
      end
  end

  ## Tests

  def root(%Conn{} = conn) do
    assert conn.method == "HEAD"
    assert conn.path_info == []
    assert conn.query_string == "foo=bar&baz=bat"
    assert conn.request_path == "/"
    resp(conn, 200, "ok")
  end

  def build(%Conn{} = conn) do
    assert {Plug.Cowboy.Conn, _} = conn.adapter
    assert conn.path_info == ["build", "foo", "bar"]
    assert conn.query_string == ""
    assert conn.scheme == :http
    assert conn.host == "127.0.0.1"
    assert conn.port == 8003
    assert conn.method == "GET"
    assert conn.remote_ip == {127, 0, 0, 1}
    assert get_http_protocol(conn) == :"HTTP/1.1"
    resp(conn, 200, "ok")
  end

  test "builds a connection" do
    assert {200, _, _} = request(:head, "/?foo=bar&baz=bat")
    assert {200, _, _} = request(:get, "/build/foo/bar")
    assert {200, _, _} = request(:get, "//build//foo//bar")
  end

  def return_request_path(%Conn{} = conn) do
    resp(conn, 200, conn.request_path)
  end

  test "request_path" do
    assert {200, _, "/return_request_path/foo"} = request(:get, "/return_request_path/foo?barbat")

    assert {200, _, "/return_request_path/foo/bar"} =
             request(:get, "/return_request_path/foo/bar?bar=bat")

    assert {200, _, "/return_request_path/foo/bar/"} =
             request(:get, "/return_request_path/foo/bar/?bar=bat")

    assert {200, _, "/return_request_path/foo//bar"} =
             request(:get, "/return_request_path/foo//bar")

    assert {200, _, "//return_request_path//foo//bar//"} =
             request(:get, "//return_request_path//foo//bar//")
  end

  def headers(conn) do
    assert get_req_header(conn, "foo") == ["bar"]
    assert get_req_header(conn, "baz") == ["bat"]
    resp(conn, 200, "ok")
  end

  test "stores request headers" do
    assert {200, _, _} = request(:get, "/headers", [{"foo", "bar"}, {"baz", "bat"}])
  end

  def set_cookies(%Conn{} = conn) do
    conn
    |> put_resp_cookie("foo", "bar")
    |> put_resp_cookie("bar", "bat")
    |> resp(200, conn.request_path)
  end

  test "set cookies" do
    assert {200, headers, _} = request(:get, "/set_cookies")

    assert for({"set-cookie", value} <- headers, do: value) ==
             ["bar=bat; path=/; HttpOnly", "foo=bar; path=/; HttpOnly"]
  end

  def telemetry(conn) do
    Process.sleep(30)
    send_resp(conn, 200, "TELEMETRY")
  end

  def telemetry_exception(conn) do
    # send first because of the `rescue` in `call`
    send_resp(conn, 200, "Fail")
    raise "BadTimes"
  end

  def telemetry_send(event, measurements, metadata, test) do
    send(test, {:telemetry, event, measurements, metadata})
  end

  test "emits telemetry events for start/stop" do
    :telemetry.attach_many(
      :start_stop_test,
      [
        [:cowboy, :request, :start],
        [:cowboy, :request, :stop],
        [:cowboy, :request, :exception]
      ],
      &__MODULE__.telemetry_send/4,
      self()
    )

    assert {200, _, "TELEMETRY"} = request(:get, "/telemetry?foo=bar")

    assert_receive {:telemetry, [:cowboy, :request, :start], %{system_time: _},
                    %{streamid: _, req: req}}

    assert req.path == "/telemetry"

    assert_receive {:telemetry, [:cowboy, :request, :stop], %{duration: duration},
                    %{streamid: _, req: ^req}}

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    assert duration_ms >= 30
    assert duration_ms < 100

    refute_received {:telemetry, [:cowboy, :request, :exception], _, _}

    :telemetry.detach(:start_stop_test)
  end

  @tag :capture_log
  test "emits telemetry events for exception" do
    :telemetry.attach_many(
      :exception_test,
      [
        [:cowboy, :request, :start],
        [:cowboy, :request, :exception]
      ],
      &__MODULE__.telemetry_send/4,
      self()
    )

    request(:get, "/telemetry_exception")

    assert_receive {:telemetry, [:cowboy, :request, :start], _, _}

    assert_receive {:telemetry, [:cowboy, :request, :exception], %{},
                    %{kind: :exit, reason: _reason, stacktrace: _stacktrace}}

    :telemetry.detach(:exception_test)
  end

  test "emits telemetry events for cowboy early_error" do
    :telemetry.attach(
      :early_error_test,
      [:cowboy, :request, :early_error],
      &__MODULE__.telemetry_send/4,
      self()
    )

    assert capture_log(fn ->
             cookie = "bar=" <> String.duplicate("a", 8_000_000)
             response = request(:get, "/headers", [{"cookie", cookie}])
             assert match?({431, _, _}, response) or match?({:error, :closed}, response)
             assert {200, _, _} = request(:get, "/headers", [{"foo", "bar"}, {"baz", "bat"}])
           end) =~ "Cowboy returned 431 because it was unable to parse the request headers"

    assert_receive {:telemetry, [:cowboy, :request, :early_error],
                    %{
                      system_time: _
                    },
                    %{
                      reason: {:connection_error, :limit_reached, _},
                      partial_req: %{}
                    }}

    :telemetry.detach(:early_error_test)
  end

  def send_200(conn) do
    assert conn.state == :unset
    assert conn.resp_body == nil
    conn = send_resp(conn, 200, "OK")
    assert conn.state == :sent
    assert conn.resp_body == nil
    conn
  end

  def send_418(conn) do
    send_resp(conn, 418, "")
  end

  def send_998(conn) do
    send_resp(conn, 998, "")
  end

  def send_500(conn) do
    conn
    |> delete_resp_header("cache-control")
    |> put_resp_header("x-sample", "value")
    |> send_resp(500, ["ERR", ["OR"]])
  end

  test "sends a response with status, headers and body" do
    assert {200, headers, "OK"} = request(:get, "/send_200")

    assert List.keyfind(headers, "cache-control", 0) ==
             {"cache-control", "max-age=0, private, must-revalidate"}

    assert {500, headers, "ERROR"} = request(:get, "/send_500")
    assert List.keyfind(headers, "cache-control", 0) == nil
    assert List.keyfind(headers, "x-sample", 0) == {"x-sample", "value"}
  end

  test "allows customized statuses based on config" do
    assert {998, _headers, ""} = request(:get, "/send_998")
    {:ok, ref} = :hackney.get("http://127.0.0.1:8003/send_998", [], "", async: :once)
    assert_receive({:hackney_response, ^ref, {:status, 998, "Not An RFC Status Code"}})
    :hackney.close(ref)
  end

  test "existing statuses can be customized" do
    assert {418, _headers, ""} = request(:get, "/send_418")
    {:ok, ref} = :hackney.get("http://127.0.0.1:8003/send_418", [], "", async: :once)
    assert_receive({:hackney_response, ^ref, {:status, 418, "Totally not a teapot"}})
    :hackney.close(ref)
  end

  test "skips body on head" do
    assert {200, _, nil} = request(:head, "/send_200")
  end

  def send_file(conn) do
    conn = send_file(conn, 200, __ENV__.file)
    assert conn.state == :file
    assert conn.resp_body == nil
    conn
  end

  test "sends a file with status and headers" do
    assert {200, headers, body} = request(:get, "/send_file")
    assert body =~ "sends a file with status and headers"

    assert List.keyfind(headers, "cache-control", 0) ==
             {"cache-control", "max-age=0, private, must-revalidate"}

    assert List.keyfind(headers, "content-length", 0) ==
             {
               "content-length",
               __ENV__.file |> File.stat!() |> Map.fetch!(:size) |> Integer.to_string()
             }
  end

  test "skips file on head" do
    assert {200, _, nil} = request(:head, "/send_file")
  end

  def send_chunked(conn) do
    conn = send_chunked(conn, 200)
    assert conn.state == :chunked
    {:ok, conn} = chunk(conn, "HELLO\n")
    {:ok, conn} = chunk(conn, ["WORLD", ["\n"]])
    conn
  end

  test "sends a chunked response with status and headers" do
    assert {200, headers, "HELLO\nWORLD\n"} = request(:get, "/send_chunked")

    assert List.keyfind(headers, "cache-control", 0) ==
             {"cache-control", "max-age=0, private, must-revalidate"}

    assert List.keyfind(headers, "transfer-encoding", 0) == {"transfer-encoding", "chunked"}
  end

  def inform(conn) do
    conn
    |> inform(103, [{"link", "</style.css>; rel=preload; as=style"}])
    |> send_resp(200, "inform")
  end

  test "inform will not raise even though the adapter doesn't implement it" do
    # the _body in this response is actually garbled. this is a bug in the HTTP/1.1 client and not in plug
    assert {103, [{"link", "</style.css>; rel=preload; as=style"}], _body} =
             request(:get, "/inform")
  end

  def upgrade_unsupported(conn) do
    conn
    |> upgrade_adapter(:unsupported, opt: :unsupported)
  end

  test "upgrade will not set the response" do
    assert {500, _, body} = request(:get, "/upgrade_unsupported")
    assert body =~ "upgrade to unsupported not supported by Plug.Cowboy.Conn"
  end

  defmodule NoopWebSocketHandler do
    @behaviour :cowboy_websocket

    # We never actually call this; it's just here to quell compiler warnings
    @impl true
    def init(req, state), do: {:cowboy_websocket, req, state}

    @impl true
    def websocket_handle(_frame, state), do: {:ok, state}

    @impl true
    def websocket_info(_msg, state), do: {:ok, state}
  end

  def upgrade_websocket(conn) do
    # In actual use, it's the caller's responsibility to ensure the upgrade is valid before
    # calling upgrade_adapter
    conn
    |> upgrade_adapter(:websocket, {NoopWebSocketHandler, [], %{}})
  end

  test "upgrades the connection when the connection is a valid websocket" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 8003, active: false, mode: :binary)

    :gen_tcp.send(socket, """
    GET /upgrade_websocket HTTP/1.1\r
    Host: server.example.com\r
    Upgrade: websocket\r
    Connection: Upgrade\r
    Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
    Sec-WebSocket-Version: 13\r
    \r
    """)

    {:ok, response} = :gen_tcp.recv(socket, 234)

    assert [
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

  test "returns error in cases where an upgrade is indicated but the connection is not a valid upgrade" do
    assert {426, _headers, ""} = request(:get, "/upgrade_websocket")
  end

  def push(conn) do
    conn
    |> push("/static/assets.css")
    |> send_resp(200, "push")
  end

  test "push will not raise even though the adapter doesn't implement it" do
    assert {200, _headers, "push"} = request(:get, "/push")
  end

  def push_or_raise(conn) do
    conn
    |> push!("/static/assets.css")
    |> send_resp(200, "push or raise")
  end

  test "push will raise because it is not implemented" do
    assert {200, _headers, "push or raise"} = request(:get, "/push_or_raise")
  end

  def read_req_body(conn) do
    expected = :binary.copy("abcdefghij", 100_000)
    assert {:ok, ^expected, conn} = read_body(conn)
    assert {:ok, "", conn} = read_body(conn)
    resp(conn, 200, "ok")
  end

  def read_req_body_partial(conn) do
    # Read something even with no length
    assert {:more, body, conn} = read_body(conn, length: 0, read_length: 1_000)
    assert byte_size(body) > 0
    assert {:more, body, conn} = read_body(conn, length: 5_000, read_length: 1_000)
    assert byte_size(body) > 0
    assert {:more, body, conn} = read_body(conn, length: 20_000, read_length: 1_000)
    assert byte_size(body) > 0
    assert {:ok, body, conn} = read_body(conn, length: 2_000_000)
    assert byte_size(body) > 0

    # Once it is over, always returns :ok
    assert {:ok, "", conn} = read_body(conn, length: 2_000_000)
    assert {:ok, "", conn} = read_body(conn, length: 0)

    resp(conn, 200, "ok")
  end

  test "reads body" do
    body = :binary.copy("abcdefghij", 100_000)
    assert {200, _, "ok"} = request(:post, "/read_req_body_partial", [], body)
    assert {200, _, "ok"} = request(:get, "/read_req_body", [], body)
    assert {200, _, "ok"} = request(:post, "/read_req_body", [], body)
  end

  def multipart(conn) do
    opts = Plug.Parsers.init(parsers: [Plug.Parsers.MULTIPART], length: 8_000_000)
    conn = Plug.Parsers.call(conn, opts)
    assert conn.params["name"] == "hello"
    assert conn.params["status"] == ["choice1", "choice2"]
    assert conn.params["empty"] == nil

    assert %Plug.Upload{} = file = conn.params["pic"]
    assert File.read!(file.path) == "hello\n\n"
    assert file.content_type == "text/plain"
    assert file.filename == "foo.txt"

    resp(conn, 200, "ok")
  end

  test "parses multipart requests" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    hello\r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"pic\"; filename=\"foo.txt\"\r
    Content-Type: text/plain\r
    \r
    hello

    \r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"empty\"; filename=\"\"\r
    Content-Type: application/octet-stream\r
    \r
    \r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name="status[]"\r
    \r
    choice1\r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name="status[]"\r
    \r
    choice2\r
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"commit\"\r
    \r
    Create User\r
    ------w58EW1cEpjzydSCq--\r
    """

    headers = [
      {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
      {"Content-Length", byte_size(multipart)}
    ]

    assert {200, _, _} = request(:post, "/multipart", headers, multipart)
    assert {200, _, _} = request(:post, "/multipart?name=overriden", headers, multipart)
  end

  def file_too_big(conn) do
    opts = Plug.Parsers.init(parsers: [Plug.Parsers.MULTIPART], length: 5)
    conn = Plug.Parsers.call(conn, opts)

    assert %Plug.Upload{} = file = conn.params["pic"]
    assert File.read!(file.path) == "hello\n\n"
    assert file.content_type == "text/plain"
    assert file.filename == "foo.txt"

    resp(conn, 200, "ok")
  end

  test "returns parse error when file pushed the boundaries in multipart requests" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"pic\"; filename=\"foo.txt\"\r
    Content-Type: text/plain\r
    \r
    hello

    \r
    ------w58EW1cEpjzydSCq--\r
    """

    headers = [
      {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
      {"Content-Length", byte_size(multipart)}
    ]

    assert {500, _, body} = request(:post, "/file_too_big", headers, multipart)
    assert body =~ "the request is too large"
  end

  test "validates utf-8 on multipart requests" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    #{<<139>>}\r
    ------w58EW1cEpjzydSCq\r
    """

    headers = [
      {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
      {"Content-Length", byte_size(multipart)}
    ]

    assert {500, _, body} = request(:post, "/multipart", headers, multipart)
    assert body =~ "invalid UTF-8 on multipart body, got byte 139"
  end

  test "returns parse error when body is badly formatted in multipart requests" do
    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    ------w58EW1cEpjzydSCq\r
    """

    headers = [
      {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
      {"Content-Length", byte_size(multipart)}
    ]

    assert {500, _, body} = request(:post, "/multipart", headers, multipart)

    assert body =~
             "malformed request, a RuntimeError exception was raised with message \"invalid multipart"

    multipart = """
    ------w58EW1cEpjzydSCq\r
    Content-Disposition: form-data; name=\"name\"\r
    \r
    hello
    """

    headers = [
      {"Content-Type", "multipart/form-data; boundary=----w58EW1cEpjzydSCq"},
      {"Content-Length", byte_size(multipart)}
    ]

    assert {500, _, body} = request(:post, "/multipart", headers, multipart)

    assert body =~
             "malformed request, a RuntimeError exception was raised with message \"invalid multipart"
  end

  def http2(conn) do
    case conn.query_string do
      "noinfer" <> _ ->
        conn
        |> push("/static/assets.css", [{"accept", "text/plain"}])
        |> send_resp(200, Atom.to_string(get_http_protocol(conn)))

      "earlyhints" <> _ ->
        conn
        |> inform(:early_hints, [{"link", "</style.css>; rel=preload; as=style"}])
        |> send_resp(200, Atom.to_string(get_http_protocol(conn)))

      _ ->
        conn
        |> push("/static/assets.css")
        |> send_resp(200, Atom.to_string(get_http_protocol(conn)))
    end
  end

  def peer_data(conn) do
    assert conn.scheme == :https
    %{address: address, port: port, ssl_cert: ssl_cert} = get_peer_data(conn)
    assert address == {127, 0, 0, 1}
    assert is_integer(port)
    assert is_binary(ssl_cert)
    send_resp(conn, 200, "OK")
  end

  test "exposes peer data" do
    pool = :client_ssl_pool
    pool_opts = [timeout: 150_000, max_connections: 10]
    :ok = :hackney_pool.start_pool(pool, pool_opts)

    opts = [
      pool: :client_ssl_pool,
      ssl_options: [server_name_indication: ~c"localhost"] ++ @client_ssl_opts
    ]

    assert {:ok, 200, _headers, client} =
             :hackney.get("https://127.0.0.1:8004/peer_data", [], "", opts)

    assert {:ok, "OK"} = :hackney.body(client)
    :hackney.close(client)
  end

  ## Helpers

  defp request(:head = verb, path) do
    {:ok, status, headers} = :hackney.request(verb, "http://127.0.0.1:8003" <> path, [], "", [])
    {status, headers, nil}
  end

  defp request(verb, path, headers \\ [], body \\ "") do
    case :hackney.request(verb, "http://127.0.0.1:8003" <> path, headers, body, []) do
      {:ok, status, headers, client} ->
        {:ok, body} = :hackney.body(client)
        :hackney.close(client)
        {status, headers, body}

      {:error, _} = error ->
        error
    end
  end
end
