defmodule Plug.Cowboy.MixProject do
  use Mix.Project

  @version "1.0.0"
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
      {:plug, "~> 1.7"},
      {:cowboy, "~> 1.0"},
      {:ex_doc, "~> 0.19.1", only: :docs},
      {:hackney, "~> 1.2.0", only: :test}
    ]
  end

  defp package do
    %{
      licenses: ["Apache 2"],
      maintainers: ["José Valim", "Gary Rennie"],
      links: %{"GitHub" => "https://github.com/elixir-plug/plug_cowboy"},
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", ".formatter.exs"]
    }
  end
end
