defmodule Sailor.SSBServer do
  use Task, restart: :transient

  require Logger

  # TODO: Rewrite as `GenServer` and make socket active

  def start_link([port, identity, network_key]) do
    Task.start_link(__MODULE__, :accept, [port, identity, network_key])
  end

  def accept(port, identity, network_key) do
    Logger.info "Accepting peer connections via TCP on port #{port}"
    with {:ok, listen_socket} <- :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
    do
      acceptor_loop(listen_socket, identity, network_key)
    else
      {:error, :eaddrinuse} ->
        Logger.error "Can't start SSBServer: Address in use"
        :ok
    end
  end

  defp acceptor_loop(socket, our_identity, network_identifier) do
    {:ok, client_socket} = :gen_tcp.accept(socket)
    ip_port = case :inet.peername(client_socket) do
      {:ok, {:local, sockname}} -> sockname
      {:ok, {ip, port}} -> "#{:inet.ntoa(ip)}:#{port}"
      _ -> "unknown"
    end
    Logger.info "Client connected from #{ip_port}"

    Task.start(fn ->
      case Sailor.PeerConnection.start_incoming(client_socket, our_identity, network_identifier) do
        {:ok, peer} -> Logger.info "Started peer #{inspect peer}"
        {:error, {:already_started, pid}} -> Logger.error "Peer with same identity already connected as process #{inspect pid}"
        error -> Logger.error "Error starting peer: #{inspect error}"
      end
    end)
    # :ok = :gen_tcp.controlling_process(client_socket, peer)
    # :ok = Sailor.PeerConnection.run(peer, client_socket, our_identity, :server)

    acceptor_loop(socket, our_identity, network_identifier)
  end
end
