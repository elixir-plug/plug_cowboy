defmodule Plug.Cowboy.Handler do
  @moduledoc false
  @connection Plug.Cowboy.Conn
  @already_sent {:plug_conn, :sent}

  def init(req, {plug, opts}) do
    start = System.monotonic_time()
    :telemetry.execute([:plug_adapter, :request, :start], %{name: :plug_cowboy, start_time: System.system_time()})

    conn = @connection.conn(req)

    try do
      %{adapter: {@connection, req}} =
        conn
        |> plug.call(opts)
        |> maybe_send(plug)

      {:ok, req, {plug, opts}}
    catch
      kind, reason ->
        stacktrace = System.stacktrace()
        metadata = %{kind: kind, error: reason, stacktrace: stacktrace, name: :plug_cowboy}
        measurements = %{duration: System.monotonic_time() - start}
        :telemetry.execute([:plug_adapter, :request, :failure], measurements, metadata)

        exit_on_error(kind, reason, stacktrace, {plug, :call, [conn, opts]})
    after
      receive do
        @already_sent -> :ok
      after
        0 ->
          :ok
      end
    else
      result ->
        measurements = %{duration: System.monotonic_time() - start}
        :telemetry.execute([:plug_adapter, :request, :stop], measurements, %{name: :plug_cowboy})
        result
    end
  end

  defp exit_on_error(
         :error,
         %Plug.Conn.WrapperError{kind: kind, reason: reason, stack: stack},
         _stack,
         call
       ) do
    exit_on_error(kind, reason, stack, call)
  end

  defp exit_on_error(:error, value, stack, call) do
    exception = Exception.normalize(:error, value, stack)
    exit({{exception, stack}, call})
  end

  defp exit_on_error(:throw, value, stack, call) do
    exit({{{:nocatch, value}, stack}, call})
  end

  defp exit_on_error(:exit, value, _stack, call) do
    exit({value, call})
  end

  defp maybe_send(%Plug.Conn{state: :unset}, _plug), do: raise(Plug.Conn.NotSentError)
  defp maybe_send(%Plug.Conn{state: :set} = conn, _plug), do: Plug.Conn.send_resp(conn)
  defp maybe_send(%Plug.Conn{} = conn, _plug), do: conn

  defp maybe_send(other, plug) do
    raise "Cowboy2 adapter expected #{inspect(plug)} to return Plug.Conn but got: " <>
            inspect(other)
  end
end
