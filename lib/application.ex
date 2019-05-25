defmodule Sailor.Application do
  use Application

  def start(_type, _args) do
    {:ok, identity_keypair} = Sailor.Keypair.load_secret Application.get_env(:sailor, :identity_file)
    {:ok, network_key} = Base.decode64(Application.get_env(:sailor, :network_key))
    port = Application.get_env(:sailor, :port)

    rpc_handlers = [
      {Sailor.Rpc.Handler.Blobs, ["/tmp/sailor_blobs"]}
    ]

    children = [
      {Sailor.LocalIdentity, [identity_keypair, network_key]},

      {DynamicSupervisor, strategy: :one_for_one, name: Sailor.PeerConnectionSupervisor},
      {Sailor.PeerConnection.Registry, []},

      Sailor.Gossip, # Do we need this when we have `Sailor.PeerConnection.Registry`?
      # TODO: Don't start LocalDiscover for tests
      {Sailor.LocalDiscovery, [port, identity_keypair]},

      {Sailor.Rpc.HandlerRegistry, []},
      %{id: Sailor.RpcHandler.Supervisor, start: {Supervisor, :start_link, [rpc_handlers, [{:strategy, :one_for_one}]]}},
      {Sailor.SSBServer, [port, identity_keypair, network_key]},
    ]

    opts = [strategy: :one_for_one, name: Sailor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
