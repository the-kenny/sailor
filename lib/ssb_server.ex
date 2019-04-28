defmodule Sailor.SSBServer do
  use Task, restart: :permanent

  require Logger


  def start_link([port, identity]) do
    Task.start_link(__MODULE__, :accept, [port, identity])
  end

  def accept(port, identity) do
    {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
    Logger.info "Listening for peers on port #{inspect port}"
    acceptor_loop(listen_socket, identity)
  end

  defp acceptor_loop(socket, identity) do
    {:ok, client_socket} = :gen_tcp.accept(socket)
    Logger.info "Got Client on: #{inspect client_socket}"

    {:ok, peer} = DynamicSupervisor.start_child(Sailor.PeerSupervisor, {Sailor.Peer, [client_socket, identity, :server]})
    :ok = :gen_tcp.controlling_process(client_socket, peer)

    acceptor_loop(socket, identity)
  end
end
