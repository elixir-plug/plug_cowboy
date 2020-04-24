defmodule Plug.Cowboy.Stream do
  @moduledoc false

  require Logger

  def init(stream_id, req, opts) do
    :cowboy_stream_h.init(stream_id, req, opts)
  end

  def data(stream_id, is_fin, data, state) do
    :cowboy_stream_h.data(stream_id, is_fin, data, state)
  end

  def info(stream_id, info, state) do
    :cowboy_stream_h.info(stream_id, info, state)
  end

  def terminate(_stream_id, _reason, :undefined) do
    :ok
  end

  def terminate(stream_id, reason, state) do
    :cowboy_stream_h.info(stream_id, reason, state)
    :ok
  end

  def early_error(_stream_id, reason, partial_req, resp, _opts) do
    case reason do
      {:connection_error, :limit_reached, specific_reason} ->
        Logger.error("""
        Cowboy returned 431 because it was unable to parse the request headers.

        This may happen because there are no headers, or there are too many headers
        or the header name or value are too large (such as a large cookie).

        More specific reason is:

            #{inspect(specific_reason)}

        You can customize those limits when configuring your http/https
        server. The configuration option and default values are shown below:

            protocol_options: [
              max_header_name_length: 64,
              max_header_value_length: 4096,
              max_headers: 100
            ]

        Request info:

            peer: #{format_peer(partial_req.peer)}
            method: #{Map.get(partial_req, :method, "<unable to parse>")}
            path: #{Map.get(partial_req, :path, "<unable to parse>")}
        """)

      _ ->
        :ok
    end

    resp
  end

  defp format_peer({addr, port}) do
    "#{:inet_parse.ntoa(addr)}:#{port}"
  end
end
