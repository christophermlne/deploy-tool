import Config

# Development-specific configuration

# For development, we run on localhost:4000
config :deploy, DeployWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_that_is_at_least_64_bytes_long_for_development_use_only",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:deploy, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:deploy, ~w(--watch)]}
  ]

# Live reload configuration
config :deploy, DeployWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/deploy_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
