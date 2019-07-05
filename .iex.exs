
defmodule User do
  alias Sailor.Peer

  # def create_peer(ip, port, other_identity, register? \\ false) do
  #   # {:ok, socket} = :gen_tcp.connect({127,0,0,1}, 8008, [:binary, active: false])

  #   random_keypair = Sailor.Keypair.random
  #   {:ok, socket, handshake} = Peer.Handshake.outgoing(
  #     {ip, port, other_identity.pub},
  #     random_keypair,
  #     Sailor.LocalIdentity.network_identifier
  #   )

  #   {:ok, peer} = Peer.start_link({socket, handshake}, register?)
  #   # :ok = Peer.run(peer, socket, random_keypair, {:client, Sailor.LocalIdentity.keypair().pub})
  #   {:ok, peer}
  # end

  # def local_test_pair() do
  #   port = Application.get_env(:sailor, :port)
  #   create_peer({127,0,0,1}, port, Sailor.LocalIdentity.keypair)
  # end

  # def test_pair(ip, port, other_identifier) do
  #   {:ok, other_identity} = Sailor.Keypair.from_identifier(other_identifier)
  #   create_peer(ip, port, other_identity)
  # end

  def outgoing_peer(ip, port, other_identifier) do
    {:ok, other_identity} = Sailor.Keypair.from_identifier(other_identifier)
    Peer.start_outgoing(
      ip,
      port,
      other_identity,
      Sailor.LocalIdentity.keypair(),
      Sailor.LocalIdentity.network_identifier()
    )
  end

  @me "@mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=.ed25519"

  def me(), do: @me

  def outgoing_peer() do
    case User.outgoing_peer({127,0,0,1}, 8008, @me) do
      {:ok, peer} -> peer
    end
  end

  def dump_all_peers() do
    peers = Sailor.Stream.for_peer(@me)
    |> Sailor.Stream.extract_peers()

    User.outgoing_peer({127,0,0,1}, 8008, @me)
    peer = GenServer.whereis(Peer.for_identifier(@me))

    peers
    |> Stream.each(&Sailor.Peer.Tasks.DumpFeed.run(peer, &1))
    |> Stream.run()
  end

  # {:ok, peer} = User.outgoing_peer({127,0,0,1}, 8008, "@mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=.ed25519");
  # User.create_history_stream(peer) |> Stream.each(&IO.inspect(&1)) |> Stream.each(&Sailor.Database.store(&1)) |> Stream.run
end
