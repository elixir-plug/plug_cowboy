import Config

if Mix.env() == :test do
  config :plug, :statuses, %{
    418 => "Totally not a teapot",
    998 => "Not An RFC Status Code"
  }

  config :logger, :console,
    colors: [enabled: false],
    metadata: [:request_id]
end
