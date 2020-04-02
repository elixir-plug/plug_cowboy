defmodule Plug.Cowboy.Handler do
  @moduledoc false
  @connection Plug.Cowboy.Conn
  @already_sent {:plug_conn, :sent}

  def init(req, {plug, opts}) do
    conn = @connection.conn(req)

    system_time = System.system_time()
    start_time_mono = System.monotonic_time()

    :telemetry.execute(
      [:plug_cowboy, :handler, :start],
      %{system_time: system_time},
      %{conn: conn}
    )

    try do
      conn =
        %{adapter: {@connection, req}} =
        plug.call(conn, opts)
        |> maybe_send(plug)

      :telemetry.execute(
        [:plug_cowboy, :handler, :stop],
        %{duration: System.monotonic_time() - start_time_mono},
        %{conn: conn}
      )

      {:ok, req, {plug, opts}}
    catch
      kind, reason ->
        stack = System.stacktrace()

        :telemetry.execute(
          [:plug_cowboy, :handler, :exception],
          %{duration: System.monotonic_time() - start_time_mono},
          %{conn: conn, kind: kind, reason: reason, stack: stack}
        )

        exit_on_error(kind, reason, stack, {plug, :call, [conn, opts]})
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
