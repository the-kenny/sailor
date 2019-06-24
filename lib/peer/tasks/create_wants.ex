defmodule Sailor.Peer.Tasks.BlobSync do
  require Logger
  alias Sailor.PeerConnection

  def run(peer) do
    {:ok, request_number} = PeerConnection.rpc_stream(peer, ["blobs", "createWants"], [])
    handle_blobs(peer, request_number)
  end

  def handle_blobs(peer, request_number) do
    receive do
      {:rpc_response, ^request_number, _, packet} ->
        IO.inspect Sailor.Rpc.Packet.body(packet)
        # TODO: Send blobs requested in `packet` to `peer`
    end

    handle_blobs(peer, request_number)
  end

end
