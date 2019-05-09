defmodule Sailor.BoxstreamTest do
  use ExUnit.Case
  doctest Sailor.Boxstream

  alias Sailor.Boxstream

  def finished_handshake() do
    alias Sailor.Handshake
    alias Sailor.Keypair
    network_identifier = Handshake.default_appkey
    server_identity = Keypair.random()
    client_identity = Keypair.random()

    server = Handshake.create(server_identity, nil, network_identifier)
    client = Handshake.create(client_identity, server_identity.pub, network_identifier)

    {:ok, server} = Handshake.verify_hello(server, Handshake.hello_challenge(client))
    {:ok, client} = Handshake.verify_hello(client, Handshake.hello_challenge(server))

    {:ok, server} = Handshake.derive_secrets(server)
    {:ok, client} = Handshake.derive_secrets(client)

    {:ok, client, client_authenticate_msg} = Handshake.client_authenticate(client)
    {:ok, server} = Handshake.verify_client_authenticate(server, client_authenticate_msg)

    {:ok, server, server_accept_msg} = Handshake.server_accept(server)
    {:ok, client} = Handshake.verify_server_accept(client, server_accept_msg)

    {server, client}
  end

  test "inc_nonce" do
    assert Boxstream.inc_nonce(<<0>>) == <<1>>
    assert Boxstream.inc_nonce(<<0, 42>>) == <<0, 43>>
    assert Boxstream.inc_nonce(<<255, 255>>) == <<0, 0>>
    assert Boxstream.inc_nonce(<<255, 0, 255>>) == <<255, 1, 0>>
    assert Boxstream.inc_nonce(:binary.copy(<<255>>, 256)) == :binary.copy(<<0>>, 256)
  end

  test "encrypt-decrypt" do
    {server, client} = finished_handshake()
    {:ok, server_encrypt, _server_decrypt} = Boxstream.create(Sailor.Handshake.boxstream_keys(server))
    {:ok, _client_encrypt, client_decrypt} = Boxstream.create(Sailor.Handshake.boxstream_keys(client))

    {:ok, _, close_msg} = Boxstream.close(server_encrypt)
    {:closed, []} = Boxstream.decrypt(client_decrypt, close_msg)

    Enum.each(1..5, fn _ ->
      assert {:ok, server_encrypt, message} = Boxstream.encrypt(server_encrypt, <<"HELLO">>)
      # Check no messages are returned and the internal state isn't changed when there is not enough data for decryption
      incomplete_message = binary_part(message, 0, byte_size(message)-2)
      assert {:ok, ^client_decrypt, [], ^incomplete_message} = Boxstream.decrypt(client_decrypt, incomplete_message)

      assert {:ok, _client_decrypt, [<<"HELLO">>], unused_bytes} = Boxstream.decrypt(client_decrypt, message)
      # Check that extra data is returned in `unused_bytes` after decryption
      assert {:ok, _client_decrypt, [<<"HELLO">>], <<"foo">>} = Boxstream.decrypt(client_decrypt, message <> <<"foo">>)
    end)
  end

  test "closing" do
    {server, client} = finished_handshake()
    {:ok, server_encrypt, _server_decrypt} = Boxstream.create(Sailor.Handshake.boxstream_keys(server))
    {:ok, _client_encrypt, client_decrypt} = Boxstream.create(Sailor.Handshake.boxstream_keys(client))

    {:ok, _, close_msg} = Boxstream.close(server_encrypt)
    {:closed, []} = Boxstream.decrypt(client_decrypt, close_msg)
    {:closed, []} = Boxstream.decrypt(client_decrypt, close_msg)
  end
end

defmodule Sailor.Boxstream.IOTest do
  use ExUnit.Case
  doctest Sailor.Boxstream

  alias Sailor.Boxstream

end
