defmodule Sailor.SSBServer do
  use Task, restart: :permanent

  require Logger


  def start_link([]) do
    port = 8008
    Task.start_link(__MODULE__, :accept, [port])
  end

  def accept(port) do
    {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
    Logger.info "Listening for peers on port #{inspect port}"
    acceptor_loop(listen_socket)
  end

  defp acceptor_loop(socket) do
    {:ok, client_socket} = :gen_tcp.accept(socket)
    Logger.info "Got Client on: #{inspect client_socket}"

    {:ok, peer} = DynamicSupervisor.start_child(Sailor.PeerSupervisor, {Sailor.Peer, client_socket})
    :ok = :gen_tcp.controlling_process(client_socket, peer)

    acceptor_loop(socket)
  end
end
