defmodule Plug.Cowboy.Stream do
  @moduledoc false

  @default_protocol_opts %{
    max_authority_length: 255,
    max_empty_lines: 5,
    max_header_name_length: 64,
    max_header_value_length: 4096,
    max_headers: 100,
    max_method_length: 32,
    max_request_line_length: 8000,
  }

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

  def early_error(_stream_id, reason, partial_req, resp, opts) do
    case reason do
      {:connection_error, :limit_reached, specific_reason} ->
        Logger.error("""
        Cowboy returned 431 because it was unable to parse the request headers.

        More specific reason is:

            #{inspect_indented(specific_reason)}

        You can customize those limits when configuring your http/https server.
        The configuration option and their effective values are shown below:

            protocol_options: #{inspect_indented(get_protocol_opts(opts))}

        Partially parsed request:

            #{inspect_indented(partial_req)}
        """)

      _ ->
        :ok
    end

    resp
  end

  defp get_protocol_opts(opts) do
    protocol_opts = opts
    |> Map.take(Map.keys(@default_protocol_opts))
    |> Keyword.new()
    @default_protocol_opts
    |> Keyword.new()
    |> Keyword.merge(protocol_opts)
  end

  defp inspect_indented(value) do
    value
    |> inspect(pretty: true)
    |> String.replace("\n", "\n    ")
  end
end
