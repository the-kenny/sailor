
defmodule User do
  alias Sailor.PeerConnection

  def create_peer(ip, port, other_identity, register? \\ false) do
    # {:ok, socket} = :gen_tcp.connect({127,0,0,1}, 8008, [:binary, active: false])

    random_keypair = Sailor.Keypair.random
    {:ok, socket, handshake} = Sailor.PeerConnection.Handshake.outgoing(
      {ip, port, other_identity.pub},
      random_keypair,
      Sailor.LocalIdentity.network_identifier
    )

    {:ok, peer} = Peer.start_link({socket, handshake}, register?)
    # :ok = Peer.run(peer, socket, random_keypair, {:client, Sailor.LocalIdentity.keypair().pub})
    {:ok, peer}
  end

  def local_test_pair() do
    port = Application.get_env(:sailor, :port)
    create_peer({127,0,0,1}, port, Sailor.LocalIdentity.keypair)
  end

  def test_pair(ip, port, other_pubkey) do
    {:ok, other_identity} = Sailor.Keypair.from_identifier(other_pubkey)
    create_peer(ip, port, other_identity)
  end

  def outgoing_peer(ip, port, other_pubkey) do
    {:ok, other_identity} = Sailor.Keypair.from_identifier(other_pubkey)
    {:ok, peer} = Peer.start_outgoing(
      ip,
      port,
      other_identity,
      Sailor.LocalIdentity.keypair(),
      Sailor.LocalIdentity.network_identifier()
    )

    {:ok, peer}
  end

  def test(peer) do
    # {:ok, peer} = User.outgoing_peer('pub.t4l3.net', 8008, "@WndnBREUvtFVF14XYEq01icpt91753bA+nVycEJIAX4=.ed25519");
    {:ok, request_number} = Sailor.PeerConnection.rpc_stream(peer, "createHistoryStream", [%{"id" => "@WndnBREUvtFVF14XYEq01icpt91753bA+nVycEJIAX4=.ed25519"}])

    receive do
      {:rpc_response, ^request_number, packet} ->
        {:ok, message} = Sailor.Message.from_json(Sailor.Rpc.Packet.body(packet))
        IO.inspect message
        message
    end

  end
end
