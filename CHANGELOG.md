# Changelog

## v2.5.0

### Enhancements

  * Support the `:net` option so developers can work with keyword lists
  * Remove previously deprecated options

## v2.4.1 (2020-10-31)

### Bug fixes

  * Properly format linked exits

## v2.4.0 (2020-10-11)

### Bug fixes

  * Add [cowboy_telemetry](https://github.com/beam-telemetry/cowboy_telemetry/) as a dependency and enable it by default

## v2.3.0 (2020-06-11)

Plug.Cowboy requires Elixir v1.7 or later.

### Bug fixes

  * The telemetry events added in version v2.2.0 does not work as expected. The whole v2.2.x branch has been retired in favor of v2.3.0.

## v2.2.2 (2020-05-25)

### Enhancements

  * Emit telemetry event for Cowboy early errors
  * Improve error messages for Cowboy early errors

## v2.2.1 (2020-04-21)

### Enhancements

  * Use proper telemetry metadata for exceptions

## v2.2.0 (2020-04-21)

### Enhancements

  * Include telemetry support

## v2.1.3 (2020-04-14)

### Bug fixes

  * Properly support the :options option before removal

## v2.1.2 (2020-01-28)

### Bug fixes

  * Properly deprecate the :timeout option before removal

## v2.1.1 (2020-01-08)

### Enhancement

  * Improve docs and simplify child spec API

## v2.1.0 (2019-06-27)

### Enhancement

  * Add `Plug.Cowboy.Drainer` for connection draining

## v2.0.2 (2019-03-18)

### Enhancements

  * Unwrap `Plug.Conn.WrapperError` on handler error
  * Include `crash_reason` as logger metadata

## v2.0.1 (2018-12-13)

### Bug fixes

  * Respect `:read_length` and `:read_timeout` in `read_body` with Cowboy 2

## v2.0.0 (2018-10-20)

Extract `Plug.Adapters.Cowboy2` from Plug into `Plug.Cowboy`
