ExUnit.start(assert_receive_timeout: 200)

{:ok, _} = Application.ensure_all_started(:cowboy)
{:ok, _} = Application.ensure_all_started(:hackney)
Logger.configure_backend(:console, colors: [enabled: false], metadata: [:request_id])
