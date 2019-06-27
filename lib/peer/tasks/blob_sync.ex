defmodule Sailor.Peer.Tasks.BlobSync do
  require Logger
  alias Sailor.PeerConnection
  alias Sailor.Rpc.Packet

  def run(peer) do
    {:ok, request_number} = PeerConnection.rpc_stream(peer, ["blobs", "createWants"], [])
    {:ok, sup} = Task.Supervisor.start_link([])
    handle_blobs(peer, request_number, sup)
  end

  def handle_blobs(peer, request_number, task_supervisor) do
    receive do
      {:rpc_response, ^request_number, _, packet} ->
        :json = Packet.body_type(packet)
        {:ok, blobs} = packet |> Packet.body() |> Jason.decode()
        _wants = Enum.filter(blobs, fn {_blob, n} -> n < 0 end)
        has = Enum.filter(blobs, fn {_blob, n} -> n > 0 end)

        # TODO: Persist this information and let a separate process pull the data
        Logger.info "Peer #{PeerConnection.identifier(peer)} has: #{inspect has}"

        task_stream = Task.Supervisor.async_stream_nolink(task_supervisor, has, fn {blob, _severity} ->
          Sailor.Peer.Tasks.DownloadBlob.run(peer, blob)
        end)


        Stream.run(task_stream)
    end

    handle_blobs(peer, request_number, task_supervisor)
  end

end
