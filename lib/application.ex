defmodule Sailor.Application do
  use Application

  def start(_type, _args) do
    {:ok, identity_keypair} = Sailor.Keypair.load_secret "~/.ssb/secret"
    network_identifier = Sailor.Handshake.default_appkey
    port = 8008

    children = [
      {Sailor.LocalIdentity, [identity_keypair, network_identifier]},
      {DynamicSupervisor, strategy: :one_for_one, name: Sailor.PeerSupervisor},
      {Sailor.SSBServer, [port, identity_keypair]},
      Sailor.Gossip,
      {Sailor.LocalDiscover, [port, identity_keypair]},
    ]

    opts = [strategy: :one_for_one, name: Sailor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
