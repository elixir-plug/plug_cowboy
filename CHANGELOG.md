# Changelog

## v2.1.0

### Enhancement

  * Add `Plug.Cowboy.Drainer` for connection draining

## v2.0.2

### Enhancements

  * Unwrap `Plug.Conn.WrapperError` on handler error
  * Include `crash_reason` as logger metadata

## v2.0.1

### Bug fixes

  * Respect `:read_length` and `:read_timeout` in `read_body` with Cowboy 2

## v2.0.0

Extract `Plug.Adapters.Cowboy2` from Plug into `Plug.Cowboy`
