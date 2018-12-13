defmodule Plug.Cowboy.MixProject do
  use Mix.Project

  @version "2.0.1"
  @description "A Plug adapter for Cowboy"

  def project do
    [
      app: :plug_cowboy,
      version: @version,
      elixir: "~> 1.5",
      deps: deps(),
      package: package(),
      description: @description,
      name: "PlugCowboy",
      docs: [
        main: "Plug.Cowboy",
        source_ref: "v#{@version}",
        source_url: "https://github.com/elixir-plug/plug_cowboy"
      ]
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      extra_applications: [:logger],
      mod: {Plug.Cowboy, []}
    ]
  end

  def deps do
    [
      {:plug, "~> 1.7"},
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
      links: %{"GitHub" => "https://github.com/elixir-plug/plug_cowboy"}
    }
  end
end
