defmodule Sailor.SSBServer do
  use Task, restart: :transient

  require Logger

  # TODO: Rewrite as `GenServer` and make socket active

  def start_link([port, identity]) do
    Task.start_link(__MODULE__, :accept, [port, identity])
  end

  def accept(port, identity) do
    Logger.info "Listening for peers on port #{inspect port}"
    with {:ok, listen_socket} <- :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
    do
      acceptor_loop(listen_socket, identity, Sailor.LocalIdentity.network_identifier)
    else
      {:error, :eaddrinuse} ->
        Logger.error "Can't start SSBServer: Address in use"
        :ok
    end
  end

  defp acceptor_loop(socket, identity, network_identifier) do
    {:ok, client_socket} = :gen_tcp.accept(socket)
    Logger.info "Got Client on: #{inspect client_socket}"

    Task.start(fn ->
      {:ok, handshake} = Sailor.Peer.Handshake.incoming(client_socket, identity, network_identifier)
      {:ok, peer} = DynamicSupervisor.start_child(Sailor.PeerSupervisor, {Sailor.Peer, {client_socket, handshake}})
      Logger.info "Started peer #{inspect peer}"
    end)
    # :ok = :gen_tcp.controlling_process(client_socket, peer)
    # :ok = Sailor.Peer.run(peer, client_socket, identity, :server)

    acceptor_loop(socket, identity, network_identifier)
  end
end
