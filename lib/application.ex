defmodule Sailor.Application do
  use Application

  def start(_type, _args) do
    {:ok, identity_keypair} = Sailor.Handshake.Keypair.load_secret "~/.ssb/secret"
    network_identifier = Sailor.Handshake.default_appkey

    children = [
      {Sailor.Identity, [identity_keypair, network_identifier]},
      # Sailor.Discovery

      {DynamicSupervisor, strategy: :one_for_one, name: Sailor.PeerSupervisor},
      {Sailor.SSBServer, []}
    ]
    opts = [strategy: :one_for_one, name: Sailor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
