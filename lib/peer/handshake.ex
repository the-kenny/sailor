defmodule Sailor.Peer.Handshake do
  use Task

  alias Sailor.Handshake, as: H

  def start_link(socket, args) do
    Task.start_link(__MODULE__, :run, [socket, args])
  end

  # Server
  def run(socket, {identity, network_identifier}) do
    handshake = H.create(
      identity,
      nil,
      network_identifier
    )

    {:ok, client_hello} = :gen_tcp.recv(socket, 64)

    {:ok, handshake} = H.verify_hello(handshake, client_hello)

    server_hello = H.hello_challenge(handshake)
    :ok = :gen_tcp.send(socket, server_hello)

    {:ok, client_authenticate} = :gen_tcp.recv(socket, 112)
    {:ok, handshake} = H.verify_client_authenticate(handshake, client_authenticate)

    {:ok, handshake, server_accept} = H.server_accept(handshake)
    :ok = :gen_tcp.send(socket, server_accept)

    {:ok, handshake}
  end

  # Client
  def run(socket, {identity, other_pubkey, network_identifier}) do
    handshake = H.create(
      identity,
      other_pubkey,
      network_identifier
    )

    client_hello = H.hello_challenge(handshake)
    :ok = :gen_tcp.send(socket, client_hello)

    {:ok, server_hello} = :gen_tcp.recv(socket, 64)
    {:ok, handshake} = H.verify_hello(handshake, server_hello)

    {:ok, handshake, client_authenticate} = H.client_authenticate(handshake)
    :ok = :gen_tcp.send(socket, client_authenticate)

    {:ok, server_accept} = :gen_tcp.recv(socket, 80)
    {:ok, handshake} = H.verify_server_accept(handshake, server_accept)

    {:ok, handshake}
  end
end
