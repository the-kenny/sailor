defmodule Sailor.Application do
  use Application

  def start(_type, _args) do
    {:ok, identity_keypair} = Sailor.Keypair.load_secret(Application.get_env(:sailor, :identity_file))
    {:ok, network_key} = Base.decode64(Application.get_env(:sailor, :network_key))
    port = Application.get_env(:sailor, :port)

    data_path = Application.get_env(:sailor, :data_path)
    db_path = Path.expand(Path.join([data_path, "data.sqlite"]))

    children = [
      {Sailor.LocalIdentity, [identity_keypair, network_key]},

      {Sailor.Db, [db_path]},

      {Task.Supervisor, name: Sailor.Peer.TaskSupervisor},

      {DynamicSupervisor, strategy: :one_for_one, name: Sailor.PeerConnectionSupervisor},
      {Sailor.PeerConnection.Registry, []},

      {Sailor.LocalDiscovery, [port, identity_keypair]},

      {Sailor.Rpc.HandlerSupervisor, []},
      {Sailor.Rpc.HandlerRegistry, []},
      # %{id: Sailor.RpcHandler.Supervisor, start: {Supervisor, :start_link, [rpc_handlers, [{:strategy, :one_for_one}]]}},

      {Sailor.MessageProcessing.Supervisor, []},

      {Sailor.SSBServer, [port, identity_keypair, network_key]},
    ]

    opts = [strategy: :one_for_one, name: Sailor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
