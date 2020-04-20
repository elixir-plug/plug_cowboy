defmodule Plug.Cowboy.Handler do
  @moduledoc false
  @connection Plug.Cowboy.Conn
  @already_sent {:plug_conn, :sent}
  @adapter :plug_cowboy

  def init(req, {plug, opts}) do
    start = System.monotonic_time()
    conn = @connection.conn(req)

    :telemetry.execute(
      [:plug_adapter, :call, :start],
      %{system_time: System.system_time()},
      %{adapter: @adapter, conn: conn, plug: plug}
    )

    try do
      conn
      |> plug.call(opts)
      |> maybe_send(plug)
    catch
      kind, reason ->
        stacktrace = System.stacktrace()

        :telemetry.execute(
          [:plug_adapter, :call, :exception],
          %{duration: System.monotonic_time() - start},
          %{kind: kind, error: reason, stacktrace: stacktrace, adapter: @adapter, conn: conn, plug: plug}
        )

        exit_on_error(kind, reason, System.stacktrace(), {plug, :call, [conn, opts]})
    else
      %{adapter: {@connection, req}} = conn ->
        :telemetry.execute(
          [:plug_adapter, :call, :stop],
          %{duration: System.monotonic_time() - start},
          %{adapter: @adapter, conn: conn, plug: plug}
        )

        {:ok, req, {plug, opts}}
    after
      receive do
        @already_sent -> :ok
      after
        0 -> :ok
      end
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
