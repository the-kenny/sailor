
defmodule User do
  alias Sailor.PeerConnection

  def create_peer(ip, port, other_identity, register? \\ false) do
    # {:ok, socket} = :gen_tcp.connect({127,0,0,1}, 8008, [:binary, active: false])

    random_keypair = Sailor.Keypair.random
    {:ok, socket, handshake} = PeerConnection.Handshake.outgoing(
      {ip, port, other_identity.pub},
      random_keypair,
      Sailor.LocalIdentity.network_identifier
    )

    {:ok, peer} = PeerConnection.start_link({socket, handshake}, register?)
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
    PeerConnection.start_outgoing(
      ip,
      port,
      other_identity,
      Sailor.LocalIdentity.keypair(),
      Sailor.LocalIdentity.network_identifier()
    )
  end

  def create_history_stream(peer) do
    {:ok, _id} = PeerConnection.rpc_stream(peer, "createHistoryStream", [%{id: "@mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=.ed25519"}])
    Stream.resource(
      fn -> peer end,
      fn _peer ->
        receive do
          {:rpc_response, _sequence_number, "createHistoryStream", packet} ->
            body = Sailor.Rpc.Packet.body(packet)
            :json = Sailor.Rpc.Packet.body_type(packet)
            if Sailor.Rpc.Packet.end_or_error?(packet) do
              {:halt, []}
            else
              {:ok, message} = Sailor.Stream.Message.from_json(body)
              {[message], peer}
            end
        after
          5000 -> {:halt, peer}
        end
      end,
      fn _peer -> nil end
    )
  end

  @me "@mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=.ed25519"

  def dump(identifier \\ nil) do
    peer_identifier = @me
    history_stream = identifier || peer_identifier
    User.outgoing_peer({127,0,0,1}, 8008, peer_identifier)
    peer = GenServer.whereis(PeerConnection.for_identifier(peer_identifier))
    Sailor.Peer.Tasks.DumpMessages.start_link(peer, history_stream);
    # Sailor.PeerConnection.stop(peer)
  end

  def dump_all_peers() do

    peers = Memento.transaction!(fn -> Memento.Query.all(Sailor.Stream.Message) end)
    |> Sailor.Stream.extract_peers()
    |> Stream.into(MapSet.new())

    User.outgoing_peer({127,0,0,1}, 8008, @me)
    peer = GenServer.whereis(PeerConnection.for_identifier(@me))

    peers
    |> Stream.take(100)
    |> Stream.each(&Sailor.Peer.Tasks.DumpMessages.start_link(peer, &1))
    |> Stream.run()
  end

  def foo() do
    Memento.transaction! fn ->
      Memento.Query.select(Sailor.Stream.Message, [{:==, :author, "@mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=.ed25519"}])
      |> Enum.map(&Sailor.Stream.Message.sequence/1)
    end
  end
  # {:ok, peer} = User.outgoing_peer({127,0,0,1}, 8008, "@mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=.ed25519");
  # User.create_history_stream(peer) |> Stream.each(&IO.inspect(&1)) |> Stream.each(&Sailor.Database.store(&1)) |> Stream.run
end
