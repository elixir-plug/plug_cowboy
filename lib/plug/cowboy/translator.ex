defmodule Plug.Cowboy.Translator do
  @moduledoc false

  @doc """
  The `translate/4` function expected by custom Logger translators.
  """
  def translate(
        min_level,
        :error,
        :format,
        {~c"Ranch listener" ++ _, [ref, conn_pid, stream_id, stream_pid, reason, stack]}
      ) do
    extra = [" (connection ", inspect(conn_pid), ", stream id ", inspect(stream_id), ?)]
    translate_ranch(min_level, ref, extra, stream_pid, reason, stack)
  end

  def translate(_min_level, _level, _kind, _data) do
    :none
  end

  ## Ranch/Cowboy

  defp translate_ranch(
         min_level,
         _ref,
         extra,
         pid,
         {reason, {mod, :call, [%Plug.Conn{} = conn, _opts]}},
         _stack
       ) do
    if non_500_exception?(reason) do
      :skip
    else
      {:ok,
       [
         inspect(pid),
         " running ",
         inspect(mod),
         extra,
         " terminated\n",
         conn_info(min_level, conn)
         | Exception.format(:exit, reason, [])
       ], crash_reason: reason, domain: [:cowboy]}
    end
  end

  defp translate_ranch(_min_level, ref, extra, pid, reason, stack) do
    {:ok,
     [
       "Ranch protocol ",
       inspect(pid),
       " of listener ",
       inspect(ref),
       extra,
       " terminated\n"
       | Exception.format(:exit, reason, stack)
     ], crash_reason: reason, domain: [:cowboy]}
  end

  defp non_500_exception?({%{__exception__: true} = exception, _}) do
    Plug.Exception.status(exception) < 500
  end

  defp non_500_exception?(_), do: false

  defp conn_info(_min_level, conn) do
    [server_info(conn), request_info(conn)]
  end

  defp server_info(%Plug.Conn{host: host, port: :undefined, scheme: scheme}) do
    ["Server: ", host, ?\s, ?(, Atom.to_string(scheme), ?), ?\n]
  end

  defp server_info(%Plug.Conn{host: host, port: port, scheme: scheme}) do
    ["Server: ", host, ":", Integer.to_string(port), ?\s, ?(, Atom.to_string(scheme), ?), ?\n]
  end

  defp request_info(%Plug.Conn{method: method, query_string: query_string} = conn) do
    ["Request: ", method, ?\s, path_to_iodata(conn.request_path, query_string), ?\n]
  end

  defp path_to_iodata(path, ""), do: path
  defp path_to_iodata(path, qs), do: [path, ??, qs]
end
