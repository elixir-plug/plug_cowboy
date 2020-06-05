defmodule Plug.Cowboy.Telemetry do
  def init(stream_id, req, opts) do
    system_time = System.system_time()
    start_time = System.monotonic_time()

    :telemetry.execute([:plug_cowboy, :stream_handler, :start], %{system_time: system_time}, %{
      host: req.host,
      method: req.method,
      request_path: req.path,
      port: req.port,
      remote_ip: req.peer |> elem(0),
      scheme: req.scheme,
      req_headers: req.headers |> Map.to_list(),
      query_string: req.qs
    })

    {commands, state} = :cowboy_stream.init(stream_id, req, opts)
    {commands, [state, start_time]}
  end

  def info(stream_id, info, [state, start_time]) do
    end_time = System.monotonic_time()

    case info do
      {:response, <<status::binary-size(3)>> <> _message, headers, body} ->
        :telemetry.execute(
          [:plug_cowboy, :stream_handler, :stop],
          %{duration: end_time - start_time},
          %{
            status: status |> String.to_integer(),
            resp_headers: headers |> Map.to_list(),
            body: body
          }
        )

      {:EXIT, _pid, reason} ->
        :telemetry.execute(
          [:plug_cowboy, :stream_handler, :exception],
          %{duration: end_time - start_time},
          %{kind: :exit, reason: reason}
        )

      _ ->
        :ignore
    end

    {commands, state} = :cowboy_stream.info(stream_id, info, state)
    {commands, [state, start_time]}
  end

  def data(stream_id, is_fin, data, [state, start_time]) do
    {commands, state} = :cowboy_stream.data(stream_id, is_fin, data, state)
    {commands, [state, start_time]}
  end

  def terminate(stream_id, reason, [state, _start_time]) do
    :cowboy_stream.terminate(stream_id, reason, state)
  end

  def early_error(stream_id, reason, partial_req, resp, opts) do
    {:response, status, headers, body} = resp

    :telemetry.execute(
      [:plug_cowboy, :early_error],
      %{system_time: System.system_time()},
      %{
        reason: reason,
        request: %{method: partial_req[:method], path: partial_req[:path], peer: partial_req.peer},
        response: %{status: status, headers: headers, body: body}
      }
    )

    :cowboy_stream.early_error(stream_id, reason, partial_req, resp, opts)
  end
end
