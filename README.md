# PlugCowboy

[![Build Status](https://travis-ci.org/elixir-plug/plug_cowboy.svg?branch=master)](https://travis-ci.org/elixir-plug/plug_cowboy)

A Plug Adapter for the Erlang [Cowboy][cowboy] web server.

## Installation

You can use `plug_cowboy` in your project by adding the dependency:

```elixir
def deps do
  [
    {:plug_cowboy, "~> 2.0"},
  ]
end
```
You can then start the adapter with:

```elixir
Plug.Cowboy.http MyPlug, []
```

## Supervised handlers

The `Plug.Cowboy` module can be started as part of a supervision tree like so:

```elixir
defmodule MyApp do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      Plug.Cowboy.child_spec(scheme: :http, plug: MyRouter, port: 4001)
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Contributing

We welcome everyone to contribute to PlugCowboy and help us tackle existing issues!

Use the [issue tracker][issues] for bug reports or feature requests. You may also start a discussion on the [mailing list][ML] or the **[#elixir-lang][IRC]** channel on [Freenode][freenode] IRC. Open a [pull request][pulls] when you are ready to contribute.

When submitting a pull request you should not update the `CHANGELOG.md`.

If you are planning to contribute documentation, [please check our best practices for writing documentation][writing-docs].

Finally, remember all interactions in our official spaces follow our [Code of Conduct][code-of-conduct].

## License

PlugCowboy source code is released under Apache 2 License.
Check LICENSE file for more information.

  [issues]: https://github.com/elixir-plug/plug/issues
  [pulls]: https://github.com/elixir-plug/plug/pulls
  [ML]: https://groups.google.com/group/elixir-lang-core
  [code-of-conduct]: https://github.com/elixir-lang/elixir/blob/master/CODE_OF_CONDUCT.md
  [writing-docs]: https://hexdocs.pm/elixir/writing-documentation.html
  [IRC]: https://webchat.freenode.net/?channels=#elixir-lang
  [freenode]: https://freenode.net/
  [cowboy]: https://github.com/ninenines/cowboy
