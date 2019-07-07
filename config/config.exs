# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :logger,
  compile_time_purge_matching: [
    [module: Sailor.Rpc],
  ]

config :logger, :console,
  level: :debug,
  format: "\n$time $metadata[$level] $levelpad$message\n"

config :mnesia,
  dir: 'mnesia/#{Mix.env}/#{node()}'

config :sailor,
  network_key: "1KHLiKZvAvjbY1ziZEHMXawbCEIM6qwjCDm3VYRan/s=",
  port: 8009,
  identity_file: "./test.secret.json",
  data_path: "sailor_data/"

config :sailor, Sailor.LocalDiscovery,
  enable: true,
  broadcast_interval: 1*1000 # 0 to disable

config :sailor, Sailor.PeerConnection,
  tasks: [
    {Sailor.Peer.Tasks.DumpFeed, []},
    {Sailor.Peer.Tasks.BlobSync, []}
  ]

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# third-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :sailor, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:sailor, :key)
#
# You can also configure a third-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env()}.exs"
