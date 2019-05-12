defmodule Sailor.Application do
  use Application

  def start(_type, _args) do
    {:ok, identity_keypair} = Sailor.Keypair.load_secret "~/.ssb/secret"
    network_identifier = Sailor.Handshake.default_appkey
    port = Application.get_env(:sailor, :port)

    rpc_handlers = [
      {Sailor.Rpc.Handler.Blobs, ["/tmp/sailor_blobs"]}
    ]

    children = [
      {Sailor.LocalIdentity, [identity_keypair, network_identifier]},

      {DynamicSupervisor, strategy: :one_for_one, name: Sailor.PeerSupervisor},
      {Sailor.Peer.Registry, []},

      Sailor.Gossip, # Do we need this when we have `Sailor.Peer.Registry`?
      # TODO: Don't start LocalDiscover for tests
      {Sailor.LocalDiscovery, [port, identity_keypair]},

      {Sailor.Rpc.HandlerRegistry, []},
      %{id: Sailor.RpcHandler.Supervisor, start: {Supervisor, :start_link, [rpc_handlers, [{:strategy, :one_for_one}]]}},
      {Sailor.SSBServer, [port, identity_keypair]},
    ]

    opts = [strategy: :one_for_one, name: Sailor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
