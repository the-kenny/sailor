defmodule Sailor.PeerConnection.Handshake do
  alias Sailor.Handshake, as: H
  alias Sailor.Keypair

  require Logger

  @connect_timeout 5000

  # Server
  def incoming(socket, our_identity, network_identifier) do
    handshake = H.create(
      our_identity,
      nil,
      network_identifier
    )

    {:ok, client_hello} = :gen_tcp.recv(socket, 64)

    {:ok, handshake} = H.verify_hello(handshake, client_hello)

    {:ok, handshake} = H.derive_secrets(handshake)

    server_hello = H.hello_challenge(handshake)
    :ok = :gen_tcp.send(socket, server_hello)

    {:ok, client_authenticate} = :gen_tcp.recv(socket, 112)
    {:ok, handshake} = H.verify_client_authenticate(handshake, client_authenticate)

    {:ok, handshake, server_accept} = H.server_accept(handshake)
    :ok = :gen_tcp.send(socket, server_accept)

    Logger.info "Successful handshake between #{Keypair.identifier(handshake.identity)} (us) and #{Keypair.identifier(Keypair.from_pubkey(handshake.other_pubkey))} (them)"

    {:ok, handshake}
  end

  # Client
  def outgoing({ip, port, other_pubkey}, identity, network_identifier) do
    {:ok, socket} = :gen_tcp.connect(ip, port, [:binary, active: false], @connect_timeout)

    handshake = H.create(
      identity,
      other_pubkey,
      network_identifier
    )

    client_hello = H.hello_challenge(handshake)
    :ok = :gen_tcp.send(socket, client_hello)

    {:ok, server_hello} = :gen_tcp.recv(socket, 64)
    {:ok, handshake} = H.verify_hello(handshake, server_hello)

    {:ok, handshake} = H.derive_secrets(handshake)

    {:ok, handshake, client_authenticate} = H.client_authenticate(handshake)
    :ok = :gen_tcp.send(socket, client_authenticate)

    {:ok, server_accept} = :gen_tcp.recv(socket, 80)
    {:ok, handshake} = H.verify_server_accept(handshake, server_accept)

    Logger.info "Successful handshake between #{Keypair.identifier(handshake.identity)} (us) and #{Keypair.identifier(Keypair.from_pubkey(handshake.other_pubkey))} (them)"

    {:ok, socket, handshake}
  end
end
