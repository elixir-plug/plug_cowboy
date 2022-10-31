import Config

if config_env() == :test do
  config :plug, :statuses, %{
    418 => "Totally not a teapot",
    998 => "Not An RFC Status Code"
  }
end
