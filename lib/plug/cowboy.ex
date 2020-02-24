defmodule Plug.Cowboy do
  @moduledoc """
  Adapter interface to the Cowboy2 webserver.

  ## Options

    * `:ip` - the ip to bind the server to.
      Must be either a tuple in the format `{a, b, c, d}` with each value in `0..255` for IPv4,
      or a tuple in the format `{a, b, c, d, e, f, g, h}` with each value in `0..65535` for IPv6,
      or a tuple in the format `{:local, path}` for a unix socket at the given `path`.

    * `:port` - the port to run the server.
      Defaults to 4000 (http) and 4040 (https).
      Must be 0 when `:ip` is a `{:local, path}` tuple.

    * `:dispatch` - manually configure Cowboy's dispatch.
      If this option is used, the given plug won't be initialized
      nor dispatched to (and doing so becomes the user's responsibility).

    * `:ref` - the reference name to be used.
      Defaults to `plug.HTTP` (http) and `plug.HTTPS` (https).
      This is the value that needs to be given on shutdown.

    * `:compress` - Cowboy will attempt to compress the response body.
      Defaults to false.

    * `:stream_handlers` - List of Cowboy `stream_handlers`,
      see [Cowboy docs](https://ninenines.eu/docs/en/cowboy/2.5/manual/cowboy_http/).

    * `:protocol_options` - Specifies remaining protocol options,
      see [Cowboy docs](https://ninenines.eu/docs/en/cowboy/2.5/manual/cowboy_http/).

    * `:transport_options` - A keyword list specifying transport options,
      see [ranch docs](https://ninenines.eu/docs/en/ranch/1.6/manual/ranch/).
      By default `:num_acceptors` will be set to `100` and `:max_connections`
      to `16_384`.

  All other options are given as `:socket_opts` to the underlying transport.
  When running on HTTPS, any SSL configuration should be given directly to the
  adapter. See `https/3` for an example and read `Plug.SSL.configure/1` to
  understand about our SSL defaults. When using a unix socket, OTP 21+ is
  required for `Plug.Static` and `Plug.Conn.send_file/3` to behave correctly.
  """

  require Logger

  @doc false
  def start(_type, _args) do
    Logger.add_translator({Plug.Cowboy.Translator, :translate})
    Supervisor.start_link([], strategy: :one_for_one)
  end

  # Made public with @doc false for testing.
  @doc false
  def args(scheme, plug, plug_opts, cowboy_options) do
    {cowboy_options, non_keyword_options} = Enum.split_with(cowboy_options, &match?({_, _}, &1))

    cowboy_options
    |> normalize_cowboy_options(scheme)
    |> to_args(scheme, plug, plug_opts, non_keyword_options)
  end

  @doc """
  Runs cowboy under http.

  ## Example

      # Starts a new interface
      Plug.Cowboy.http MyPlug, [], port: 80

      # The interface above can be shutdown with
      Plug.Cowboy.shutdown MyPlug.HTTP

  """
  @spec http(module(), Keyword.t(), Keyword.t()) ::
          {:ok, pid} | {:error, :eaddrinuse} | {:error, term}
  def http(plug, opts, cowboy_options \\ []) do
    run(:http, plug, opts, cowboy_options)
  end

  @doc """
  Runs cowboy under https.

  Besides the options described in the module documentation,
  this function sets defaults and accepts all options defined
  in `Plug.SSL.configure/2`.

  ## Example

      # Starts a new interface
      Plug.Cowboy.https MyPlug, [],
        port: 443,
        password: "SECRET",
        otp_app: :my_app,
        keyfile: "priv/ssl/key.pem",
        certfile: "priv/ssl/cert.pem",
        dhfile: "priv/ssl/dhparam.pem"

      # The interface above can be shutdown with
      Plug.Cowboy.shutdown MyPlug.HTTPS

  """
  @spec https(module(), Keyword.t(), Keyword.t()) ::
          {:ok, pid} | {:error, :eaddrinuse} | {:error, term}
  def https(plug, opts, cowboy_options \\ []) do
    Application.ensure_all_started(:ssl)
    run(:https, plug, opts, cowboy_options)
  end

  @doc """
  Shutdowns the given reference.
  """
  def shutdown(ref) do
    :cowboy.stop_listener(ref)
  end

  @transport_options [
    :connection_type,
    :handshake_timeout,
    :max_connections,
    :logger,
    :num_acceptors,
    :shutdown,
    :socket,
    :socket_opts,

    # Special cases supported by plug but not ranch
    :acceptors
  ]

  @doc """
  A function for starting a Cowboy2 server under Elixir v1.5+ supervisors.

  It supports all options as specified in the module documentation plus it
  requires the follow two options:

    * `:scheme` - either `:http` or `:https`
    * `:plug` - such as MyPlug or {MyPlug, plug_opts}

  ## Examples

  Assuming your Plug module is named `MyApp` you can add it to your
  supervision tree by using this function:

      children = [
        {Plug.Cowboy, scheme: :http, plug: MyApp, options: [port: 4040]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  """
  def child_spec(opts) do
    scheme = Keyword.fetch!(opts, :scheme)

    {plug, plug_opts} =
      case Keyword.fetch!(opts, :plug) do
        {_, _} = tuple -> tuple
        plug -> {plug, []}
      end

    # We support :options for backwards compatibility.
    cowboy_opts =
      opts
      |> Keyword.drop([:scheme, :plug, :options])
      |> Keyword.merge(Keyword.get(opts, :options, []))

    cowboy_args = args(scheme, plug, plug_opts, cowboy_opts)
    [ref, transport_opts, proto_opts] = cowboy_args

    {ranch_module, cowboy_protocol, transport_opts} =
      case scheme do
        :http ->
          {:ranch_tcp, :cowboy_clear, transport_opts}

        :https ->
          %{socket_opts: socket_opts} = transport_opts

          socket_opts =
            socket_opts
            |> Keyword.put_new(:next_protocols_advertised, ["h2", "http/1.1"])
            |> Keyword.put_new(:alpn_preferred_protocols, ["h2", "http/1.1"])

          {:ranch_ssl, :cowboy_tls, %{transport_opts | socket_opts: socket_opts}}
      end

    {id, start, restart, shutdown, type, modules} =
      :ranch.child_spec(ref, ranch_module, transport_opts, cowboy_protocol, proto_opts)

    %{id: id, start: start, restart: restart, shutdown: shutdown, type: type, modules: modules}
  end

  ## Helpers

  @protocol_options [:compress, :stream_handlers]

  defp run(scheme, plug, opts, cowboy_options) do
    case Application.ensure_all_started(:cowboy) do
      {:ok, _} ->
        nil

      {:error, {:cowboy, _}} ->
        raise "could not start the Cowboy application. Please ensure it is listed as a dependency in your mix.exs"
    end

    start =
      case scheme do
        :http -> :start_clear
        :https -> :start_tls
        other -> :erlang.error({:badarg, [other]})
      end

    apply(:cowboy, start, args(scheme, plug, opts, cowboy_options))
  end

  defp normalize_cowboy_options(cowboy_options, :http) do
    Keyword.put_new(cowboy_options, :port, 4000)
  end

  defp normalize_cowboy_options(cowboy_options, :https) do
    cowboy_options
    |> Keyword.put_new(:port, 4040)
    |> Plug.SSL.configure()
    |> case do
      {:ok, options} -> options
      {:error, message} -> fail(message)
    end
  end

  defp to_args(opts, scheme, plug, plug_opts, non_keyword_opts) do
    {timeout, opts} = Keyword.pop(opts, :timeout)

    if timeout do
      Logger.warn("the :timeout option for Cowboy webserver has no effect and must be removed")
    end

    opts = Keyword.delete(opts, :otp_app)
    {ref, opts} = Keyword.pop(opts, :ref)
    {dispatch, opts} = Keyword.pop(opts, :dispatch)
    {protocol_options, opts} = Keyword.pop(opts, :protocol_options, [])

    dispatch = :cowboy_router.compile(dispatch || dispatch_for(plug, plug_opts))
    {extra_options, opts} = Keyword.split(opts, @protocol_options)

    extra_options = set_stream_handlers(extra_options)
    protocol_and_extra_options = :maps.from_list(protocol_options ++ extra_options)
    protocol_options = Map.merge(%{env: %{dispatch: dispatch}}, protocol_and_extra_options)
    {transport_options, socket_options} = Keyword.pop(opts, :transport_options, [])

    option_keys = Keyword.keys(socket_options)

    for opt <- @transport_options, opt in option_keys do
      option_deprecation_warning(opt)
    end

    {num_acceptors, socket_options} = Keyword.pop(socket_options, :num_acceptors, 100)
    {num_acceptors, socket_options} = Keyword.pop(socket_options, :acceptors, num_acceptors)
    {max_connections, socket_options} = Keyword.pop(socket_options, :max_connections, 16_384)

    socket_options = non_keyword_opts ++ socket_options

    transport_options =
      transport_options
      |> Keyword.put_new(:num_acceptors, num_acceptors)
      |> Keyword.put_new(:max_connections, max_connections)
      |> Keyword.update(
        :socket_opts,
        socket_options,
        &(&1 ++ socket_options)
      )
      |> Map.new()

    [ref || build_ref(plug, scheme), transport_options, protocol_options]
  end

  @default_stream_handlers [Plug.Cowboy.Stream]

  defp set_stream_handlers(opts) do
    compress = Keyword.get(opts, :compress)
    stream_handlers = Keyword.get(opts, :stream_handlers)

    case {compress, stream_handlers} do
      {true, nil} ->
        Keyword.put_new(opts, :stream_handlers, [:cowboy_compress_h | @default_stream_handlers])

      {true, _} ->
        raise "cannot set both compress and stream_handlers at once. " <>
                "If you wish to set compress, please add `:cowboy_compress_h` to your stream handlers."

      {_, nil} ->
        Keyword.put_new(opts, :stream_handlers, @default_stream_handlers)

      {_, _} ->
        opts
    end
  end

  defp build_ref(plug, scheme) do
    Module.concat(plug, scheme |> to_string |> String.upcase())
  end

  defp dispatch_for(plug, opts) do
    opts = plug.init(opts)
    [{:_, [{:_, Plug.Cowboy.Handler, {plug, opts}}]}]
  end

  defp fail(message) do
    raise ArgumentError, "could not start Cowboy2 adapter, " <> message
  end

  defp option_deprecation_warning(:acceptors),
    do: option_deprecation_warning(:acceptors, :num_acceptors)

  defp option_deprecation_warning(option),
    do: option_deprecation_warning(option, option)

  defp option_deprecation_warning(option, expected_option) do
    warning =
      "using :#{option} in options is deprecated. Please pass " <>
        ":#{expected_option} to the :transport_options keyword list instead"

    IO.warn(warning)
  end
end
