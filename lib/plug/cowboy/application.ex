defmodule Plug.Cowboy.Application do
  @moduledoc false

  @doc false
  def start(_type, _args) do
    Logger.add_translator({Plug.Cowboy.Translator, :translate})
    Supervisor.start_link([], strategy: :one_for_one)
  end
end
