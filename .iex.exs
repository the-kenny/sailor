
defmodule User do
  def create_peer() do
    alias Sailor.Peer
    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, 8008, [:binary, active: false])

    {:ok, peer} = Peer.start_link([socket, {:client, Sailor.Identity.keypair().pub}])
    {:ok, peer}
  end
end
