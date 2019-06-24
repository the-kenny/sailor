defmodule Sailor.Peer.Tasks.BlobSync do
  require Logger
  alias Sailor.PeerConnection
  alias Sailor.Rpc.Packet

  def run(peer) do
    {:ok, request_number} = PeerConnection.rpc_stream(peer, ["blobs", "createWants"], [])
    handle_blobs(peer, request_number)
  end

  def handle_blobs(peer, request_number) do
    receive do
      {:rpc_response, ^request_number, _, packet} ->
        :json = Packet.body_type(packet)
        {:ok, blobs} = Packet.body(packet) |> Jason.decode()
        _wants = Enum.filter(blobs, fn {_blob, n} -> n < 0 end)
        has = Enum.filter(blobs, fn {_blob, n} -> n > 0 end)

        # TODO: Persist this information and let a separate process pull the data
        Logger.info "Peer #{PeerConnection.identifier(peer)} has: #{inspect has}"
        for {blob, _} <- has do
          Sailor.Peer.Tasks.DownloadBlob.run(peer, blob)
        end
    end

    handle_blobs(peer, request_number)
  end

end
