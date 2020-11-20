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
end
