defmodule Sailor.HandshakeTest do
  use ExUnit.Case
  require Sailor.Handshake, as: Handshake

  doctest Sailor.Handshake

  test "Handshake between our client and our server" do
    network_identifier = Handshake.default_appkey
    server_identity = Handshake.Keypair.random()
    client_identity = Handshake.Keypair.random()

    server = Handshake.create(server_identity, nil, network_identifier)
    client = Handshake.create(client_identity, server_identity.pub, network_identifier)

    {:ok, server} = Handshake.verify_hello(server, Handshake.hello_challenge(client))
    {:ok, client} = Handshake.verify_hello(client, Handshake.hello_challenge(server))

    # Verify that ephemeral pubkeys have been exchanged
    assert (server.other_ephemeral.pub == client.ephemeral.pub)
    assert (client.other_ephemeral.pub == server.ephemeral.pub)

    {:ok, server} = Handshake.derive_secrets(server)
    {:ok, client} = Handshake.derive_secrets(client)

    assert (server.shared_secret_ab == client.shared_secret_ab)
    assert (server.shared_secret_aB == client.shared_secret_aB)

    {:ok, client, client_authenticate_msg} = Handshake.client_authenticate(client)
    {:ok, server} = Handshake.verify_client_authenticate(server, client_authenticate_msg)

    assert (client.shared_secret_Ab == server.shared_secret_Ab)

    {:ok, server, server_accept_msg} = Handshake.server_accept(server)
    {:ok, client} = Handshake.verify_server_accept(client, server_accept_msg)

    # TODO: Verify all keys

    {:ok, server_shared_secret} = Handshake.shared_secret(server)
    {:ok, client_shared_secret} = Handshake.shared_secret(client)

    assert (server_shared_secret == client_shared_secret)
  end
end
