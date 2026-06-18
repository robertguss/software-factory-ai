defmodule ConveyorWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :conveyor

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  # The signing salt is not itself a secret (secret_key_base is), but it is sourced
  # from config so it is not a hardcoded literal and can be overridden at build time
  # via SESSION_SIGNING_SALT. It must be compile-time consistent because the LiveView
  # socket below captures @session_options at compile time.
  @session_options [
    store: :cookie,
    key: "_conveyor_key",
    signing_salt:
      Application.compile_env(:conveyor, [ConveyorWeb.Endpoint, :session_signing_salt]),
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :conveyor,
    gzip: false,
    only: ConveyorWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :conveyor
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ConveyorWeb.Router
end
