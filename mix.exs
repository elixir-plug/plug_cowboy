defmodule Plug.Cowboy.MixProject do
  use Mix.Project

  @version "2.0.0-dev"
  @description "A Plug adapter for Cowboy"

  def project do
    [
      app: :plug_cowboy,
      version: @version,
      elixir: "~> 1.4",
      deps: deps(),
      package: package(),
      description: @description,
      name: "PlugCowboy",
      docs: [
        extras: ["README.md"],
        main: "readme",
        source_ref: "v#{@version}",
        source_url: "https://github.com/elixir-plug/plug_cowboy"
      ]
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      extra_applications: [:logger],
      mod: {Plug.Cowboy.Application, []}
    ]
  end

  def deps do
    [
      {:plug, github: "elixir-plug/plug"},
      {:cowboy, "~> 2.5"},
      {:ex_doc, "~> 0.19.1", only: :docs},
      {:hackney, "~> 1.2.0", only: :test},
      {:kadabra, "0.3.4", only: :test}
    ]
  end

  defp package do
    %{
      licenses: ["Apache 2"],
      maintainers: ["José Valim", "Gary Rennie"],
      links: %{"GitHub" => "https://github.com/elixir-plug/plug_cowboy"},
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "src", ".formatter.exs"]
    }
  end
end
