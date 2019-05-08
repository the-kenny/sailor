
defmodule User do
  def create_peer() do
    alias Sailor.Peer
    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, 8008, [:binary, active: false])

    random_keypair = Sailor.Handshake.Keypair.random

    {:ok, peer} = Peer.start_link([])
    :ok = Peer.run(peer, socket, random_keypair, {:client, Sailor.LocalIdentity.keypair().pub})
    {:ok, peer}
  end
end
