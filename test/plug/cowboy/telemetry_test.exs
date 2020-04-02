defmodule Plug.Cowboy.TelemetryTest do
  use ExUnit.Case

  @start [:plug_cowboy, :handler, :start]
  @stop [:plug_cowboy, :handler, :stop]
  @exception [:plug_cowboy, :handler, :exception]

  defmodule TestPlugApp do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get "/raise" do
      raise "BadNews"
    end

    match _ do
      send_resp(conn, 200, "Hey!")
    end
  end

  defmodule TestHandler do
    def handle_event(event, measurements, metadata, %{pid: pid}) do
      send(pid, {event, measurements, metadata})
    end
  end

  setup context do
    :telemetry.attach_many(
      context.test,
      [@start, @stop, @exception],
      &TestHandler.handle_event/4,
      %{pid: self()}
    )

    on_exit(fn -> :telemetry.detach(context.test) end)

    :ok
  end

  test "telemetry events" do
    start_supervised!({Plug.Cowboy, scheme: :http, plug: TestPlugApp, options: [port: 8006]})

    {:ok, 200, _, _} = :hackney.request(:get, "localhost:8006/path", [], "", [])

    assert_receive {@start, _meas, %{conn: %{request_path: "/path", state: :unset}}}
    assert_receive {@stop, _meas, %{conn: %{request_path: "/path", status: 200}}}

    {:ok, 500, _, _} = :hackney.request(:get, "localhost:8006/raise", [], "", [])

    assert_receive {@start, _meas, %{conn: %{request_path: "/raise", state: :unset}}}
    assert_receive {@exception, _meas, %{conn: %{request_path: "/raise", state: :unset}}}

    # Not possible yet:
    # assert_receive {@exception, _meas, %{conn: %{request_path: "/raise", status: 500}}}
  end
end
