defmodule Sailor.HandshakeTest do
  use ExUnit.Case
  require Sailor.Handshake, as: Handshake

  doctest Sailor.Handshake


  alias Handshake.Keypair

  test "Keypair.from_id(id)" do
    {:ok, keypair} = Keypair.from_id("@ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8=.ed25519")
    assert keypair.curve == :ed25519
    assert keypair.sec == nil
    assert keypair.pub == <<100, 162, 35, 27, 111, 61, 20, 29, 223, 100, 252, 138, 126, 210, 41, 60, 206, 113, 170, 4, 145, 4, 103, 113, 7, 146, 156, 98, 160, 236, 167, 31>>
  end

  test "Keypair.from_id(id) error" do
    :error = Keypair.from_id("ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8=.ed25519")
    :error = Keypair.from_id("@ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8.ed25519")
    :error = Keypair.from_id("@ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8=")

  end


  test "Keypair.{from_secret, to_secret}" do
    keypair = Keypair.random()
    {:ok, keypair2} = keypair |> Keypair.to_secret |> Keypair.from_secret
    assert keypair == keypair2
  end

  test "Keypair.load_secret(path)" do
    {:ok, keypair} = Keypair.load_secret "priv/secret.json"
    assert Keypair.id(keypair) == "@ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8=.ed25519"
  end

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

    {:ok, server_shared_secret} = Handshake.shared_secret(server)
    {:ok, client_shared_secret} = Handshake.shared_secret(client)

    assert (server_shared_secret == client_shared_secret)

    {:ok, boxstream_client} = Handshake.boxstream_keys(client)
    {:ok, boxstream_server} = Handshake.boxstream_keys(server)

    assert boxstream_client.shared_secret == boxstream_server.shared_secret
    assert boxstream_client.encrypt_key == boxstream_server.decrypt_key
    assert boxstream_client.decrypt_key == boxstream_server.encrypt_key
  end
end
