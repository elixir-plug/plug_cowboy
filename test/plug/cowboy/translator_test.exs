defmodule Plug.Cowboy.TranslatorTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  def init(opts) do
    opts
  end

  def call(%{path_info: ["warn"]}, _opts) do
    raise Plug.Parsers.UnsupportedMediaTypeError, media_type: "foo/bar"
  end

  def call(%{path_info: ["error"]}, _opts) do
    raise "oops"
  end

  def call(%{path_info: ["linked"]}, _opts) do
    fn -> GenServer.call(:i_dont_exist, :ok) end |> Task.async() |> Task.await()
  end

  def call(%{path_info: ["exit"]}, _opts) do
    exit({:error, ["unfortunate shape"]})
  end

  def call(%{path_info: ["throw"]}, _opts) do
    throw("catch!")
  end

  @metadata_log_opts format: {__MODULE__, :metadata}, metadata: [:conn, :crash_reason, :domain]

  def metadata(_log_level, _message, _timestamp, metadata) do
    inspect(metadata, limit: :infinity)
  end

  test "ranch/cowboy 500 logs" do
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, [], port: 9001)

    output =
      capture_log(fn ->
        :hackney.get("http://127.0.0.1:9001/error", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    assert output =~ ~r"#PID<0\.\d+\.0> running Plug\.Cowboy\.TranslatorTest \(.*\) terminated"
    assert output =~ "Server: 127.0.0.1:9001 (http)"
    assert output =~ "Request: GET /"
    assert output =~ "** (exit) an exception was raised:"
    assert output =~ "** (RuntimeError) oops"
  end

  test "ranch/cowboy non-500 skips" do
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, [], port: 9002)

    output =
      capture_log(fn ->
        :hackney.get("http://127.0.0.1:9002/warn", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    refute output =~ ~r"#PID<0\.\d+\.0> running Plug\.Cowboy\.TranslatorTest \(.*\) terminated"
    refute output =~ "Server: 127.0.0.1:9002 (http)"
    refute output =~ "Request: GET /"
    refute output =~ "** (exit) an exception was raised:"
  end

  test "ranch/cowboy logs configured statuses" do
    Application.put_env(:plug_cowboy, :log_exceptions_with_status_code, [400..499])
    on_exit(fn -> Application.delete_env(:plug_cowboy, :log_exceptions_with_status_code) end)

    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, [], port: 9002)

    output =
      capture_log(fn ->
        :hackney.get("http://127.0.0.1:9002/warn", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    assert output =~ ~r"#PID<0\.\d+\.0> running Plug\.Cowboy\.TranslatorTest \(.*\) terminated"
    assert output =~ "Server: 127.0.0.1:9002 (http)"
    assert output =~ "Request: GET /"
    assert output =~ "** (exit) an exception was raised:"
    assert output =~ "** (Plug.Parsers.UnsupportedMediaTypeError) unsupported media type foo/bar"

    output =
      capture_log(fn ->
        :hackney.get("http://127.0.0.1:9002/error", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    refute output =~ ~r"#PID<0\.\d+\.0> running Plug\.Cowboy\.TranslatorTest \(.*\) terminated"
    refute output =~ "Server: 127.0.0.1:9001 (http)"
    refute output =~ "Request: GET /"
    refute output =~ "** (exit) an exception was raised:"
    refute output =~ "** (RuntimeError) oops"
  end

  test "ranch/cowboy linked logs" do
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, [], port: 9003)

    output =
      capture_log(fn ->
        :hackney.get("http://127.0.0.1:9003/linked", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    assert output =~
             ~r"Ranch protocol #PID<0\.\d+\.0> of listener Plug\.Cowboy\.TranslatorTest\.HTTP \(.*\) terminated"

    assert output =~ "exited in: GenServer.call"
    assert output =~ "** (EXIT) no process"
  end

  test "metadata in ranch/cowboy 500 logs" do
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, [], port: 9004)

    metadata =
      capture_log(@metadata_log_opts, fn ->
        :hackney.get("http://127.0.0.1:9004/error", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    assert metadata =~ "conn: %Plug.Conn{"
    assert metadata =~ "crash_reason:"
    assert metadata =~ "domain: [:cowboy]"
  end

  test "metadata opt-out ranch/cowboy 500 logs" do
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, [], port: 9004)
    Application.put_env(:plug_cowboy, :conn_in_exception_metadata, false)
    on_exit(fn -> Application.delete_env(:plug_cowboy, :conn_in_exception_metadata) end)

    metadata =
      capture_log(@metadata_log_opts, fn ->
        :hackney.get("http://127.0.0.1:9004/error", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    refute metadata =~ "conn: %Plug.Conn{"
  end

  test "metadata in ranch/cowboy linked logs" do
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, [], port: 9005)

    metadata =
      capture_log(@metadata_log_opts, fn ->
        :hackney.get("http://127.0.0.1:9005/linked", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    assert metadata =~ "crash_reason:"
    assert metadata =~ "{GenServer, :call"
    assert metadata =~ "domain: [:cowboy]"
  end

  test "metadata in ranch/cowboy exit logs" do
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, [], port: 9005)

    metadata =
      capture_log(@metadata_log_opts, fn ->
        :hackney.get("http://127.0.0.1:9005/exit", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    assert metadata =~ "crash_reason: {{:error, [\"unfortunate shape\"]}, []}"
    assert metadata =~ "domain: [:cowboy]"
  end

  test "metadata in ranch/cowboy throw logs" do
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, [], port: 9005)

    metadata =
      capture_log(@metadata_log_opts, fn ->
        :hackney.get("http://127.0.0.1:9005/throw", [], "", [])
        Plug.Cowboy.shutdown(__MODULE__.HTTP)
      end)

    assert metadata =~ "crash_reason: {{:nocatch, \"catch!\"}, "
    assert metadata =~ "domain: [:cowboy]"
  end
end
