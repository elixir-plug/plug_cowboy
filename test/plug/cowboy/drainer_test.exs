defmodule Plug.Cowboy.DrainerTest do
  use ExUnit.Case, async: true
  import Plug.Cowboy.Drainer

  test "builds child specs" do
    assert %{
             id: {Plug.Cowboy.DrainerTest, Plug.Cowboy.Drainer},
             modules: [Plug.Cowboy.Drainer],
             restart: :permanent,
             shutdown: :infinity,
             start: {Plug.Cowboy.Drainer, :start_link, [{Plug.Cowboy.DrainerTest, 1000}]},
             type: :worker
           } = child_spec(ref: __MODULE__)
  end
end
