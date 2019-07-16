defmodule Sailor.Application do
  use Application

  require Logger

  def start(_type, _args) do
    identity_file = Application.get_env(:sailor, :identity_file)

    identity_keypair = case Sailor.Keypair.load_secret(identity_file) do
      {:ok, kp} -> kp
      {:error, error} -> Logger.error "Failed to load keypair: #{inspect error}"
    end

    Logger.info "Starting with identity #{Sailor.Keypair.identifier(identity_keypair)} loaded from #{identity_file}"

    {:ok, network_key} = Base.decode64(Application.get_env(:sailor, :network_key))
    port = Application.get_env(:sailor, :port)

    data_path = Application.get_env(:sailor, :data_path)
    File.mkdir_p!(data_path)

    db_path = Path.expand(Path.join([data_path, "data.sqlite"]))

    children = [
      {Sailor.LocalIdentity, [identity_keypair, network_key]},

      {Sailor.Db, [db_path]},

      {Task.Supervisor, name: Sailor.Peer.TaskSupervisor},

      {DynamicSupervisor, strategy: :one_for_one, name: Sailor.PeerConnectionSupervisor},

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
