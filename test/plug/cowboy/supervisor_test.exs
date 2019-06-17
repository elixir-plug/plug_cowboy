defmodule Plug.Cowboy.SupervisorTest do
  use ExUnit.Case, async: true

  def init(opts) do
    opts
  end

  def call(conn, []) do
    conn = Plug.Conn.send_chunked(conn, 200)
    Process.sleep(200)
    {:ok, conn} = Plug.Conn.chunk(conn, "ok")
    conn
  end

  test "supervisor drains connections correctly" do
    Process.register(self(), __MODULE__)

    spec =
      {Plug.Cowboy,
       scheme: :http,
       plug: __MODULE__,
       options: [port: 8005, drain_timeout: 1000, drain_check_interval: 10]}

    # Supervisor and listener started
    assert {:ok, pid} = start_supervised(spec)
    assert :running == get_status()

    # Start a request that will keep a connection open for a second
    observe_state_changes()
    observe_slow_request()

    # Slow request opened
    assert_receive {:request_status, 200, start_request_timestamp}, 2000

    # Stop the supervisor to start the request draining
    start_shutdown_timestamp = timestamp()
    assert :ok == GenServer.stop(pid)
    complete_shutdown_timestamp = timestamp()

    # Draining started, but one request still open
    assert_receive {:listener_status, :suspended, suspended_timestamp}
    assert_receive {:conn, 1, open_request_timestamp}

    # Request completed
    assert_receive {:request_body, "ok", complete_request_timestamp}

    # Requests drained
    assert_receive {:conn, 0, drained_requests_timestamp}

    assert start_request_timestamp < start_shutdown_timestamp
    assert start_shutdown_timestamp < suspended_timestamp
    assert suspended_timestamp < complete_request_timestamp
    assert open_request_timestamp < complete_request_timestamp
    assert complete_request_timestamp < drained_requests_timestamp
    assert drained_requests_timestamp < complete_shutdown_timestamp
  end

  defp observe_state_changes() do
    this = __MODULE__

    Task.async(fn ->
      wait_for_connections(1)
      wait_until_listener_suspended()

      send(this, {:listener_status, get_status(), timestamp()})
      wait_for_connections(1)
      send(this, {:conn, 1, timestamp()})

      wait_for_connections(0)
      send(this, {:conn, 0, timestamp()})
    end)
  end

  defp observe_slow_request() do
    this = __MODULE__

    Task.async(fn ->
      {:ok, status, _headers, client} =
        :hackney.request(:get, "http://127.0.0.1:8005/", [], "", [:stream])

      send(this, {:request_status, status, timestamp()})
      {:ok, body} = :hackney.stream_body(client)
      send(this, {:request_body, body, timestamp()})
    end)
  end

  defp wait_for_connections(total) do
    :ranch.wait_for_connections(__MODULE__.HTTP, :==, total, 10)
  end

  defp wait_until_listener_suspended do
    Stream.repeatedly(&get_status/0)
    |> Stream.take_while(fn status -> status == :running end)
    |> Stream.run()
  end

  defp get_status do
    :ranch.get_status(__MODULE__.HTTP)
  end

  defp timestamp, do: :os.system_time(:micro_seconds)
end
