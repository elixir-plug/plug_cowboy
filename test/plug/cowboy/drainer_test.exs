defmodule Plug.Cowboy.DrainerTest do
  use ExUnit.Case, async: true
  import Plug.Cowboy.Drainer

  test "builds child specs" do
    assert %{
             id: {Plug.Cowboy.DrainerTest, Plug.Cowboy.Drainer},
             modules: [Plug.Cowboy.Drainer],
             restart: :permanent,
             shutdown: 2000,
             start: {Plug.Cowboy.Drainer, :start_link, [{Plug.Cowboy.DrainerTest, 20}]},
             type: :worker
           } == child_spec(options: [ref: __MODULE__, drain_timeout: 2000, drain_check_interval: 20])
  end
end
