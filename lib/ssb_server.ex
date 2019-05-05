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
      acceptor_loop(listen_socket, identity)
    else
      {:error, :eaddrinuse} ->
        Logger.error "Can't start SSBServer: Address in use"
        :ok
    end
  end

  defp acceptor_loop(socket, identity) do
    {:ok, client_socket} = :gen_tcp.accept(socket)
    Logger.info "Got Client on: #{inspect client_socket}"

    {:ok, peer} = DynamicSupervisor.start_child(Sailor.PeerSupervisor, {Sailor.Peer, []})
    :ok = :gen_tcp.controlling_process(client_socket, peer)
    :ok = Sailor.Peer.run(peer, client_socket, identity, :server)

    acceptor_loop(socket, identity)
  end
end
