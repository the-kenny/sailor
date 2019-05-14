
defmodule User do
  def create_peer(ip, port, register? \\ false) do
    alias Sailor.Peer
    # {:ok, socket} = :gen_tcp.connect({127,0,0,1}, 8008, [:binary, active: false])

    random_keypair = Sailor.Keypair.random
    {:ok, socket, handshake} = Sailor.Peer.Handshake.outgoing(
      {ip, port, Sailor.LocalIdentity.keypair().pub},
      random_keypair,
      Sailor.LocalIdentity.network_identifier
    )

    {:ok, peer} = Peer.start_link({socket, handshake}, register?)
    # :ok = Peer.run(peer, socket, random_keypair, {:client, Sailor.LocalIdentity.keypair().pub})
    {:ok, peer}
  end

  def create_peer() do
    create_peer({127,0,0,1}, 8008, false)
  end
end
