defmodule Sailor.Peer.Tasks.BlobSync do
  require Logger
  alias Sailor.Peer
  alias Sailor.Rpc.Packet

  def run(peer) do
    {:ok, request_number} = Peer.rpc_stream(peer, ["blobs", "createWants"], [])
    handle_blobs(peer, request_number)
  end

  def handle_blobs(peer, request_number) do
    receive do
      {:rpc_response, ^request_number, _, packet} ->
        :json = Packet.body_type(packet)
        {:ok, blobs} = packet |> Packet.body() |> Jason.decode()
        wants = Enum.filter(blobs, fn {_blob, n} -> n < 0 end)
        has = Enum.filter(blobs, fn {_blob, n} -> n > 0 end)

        identifier = Peer.identifier(peer)

        if !Enum.empty?(has) do
          # TODO: Persist this information and let a separate process pull the data
          Logger.debug "#{identifier} has: #{inspect has}"
        end

        if !Enum.empty?(wants) do
          Logger.debug "#{identifier} wants: #{inspect wants}"
        end

        task_stream = Task.Supervisor.async_stream_nolink(Sailor.Peer.TaskSupervisor, has, fn {blob, _severity} ->
          Sailor.Peer.Tasks.DownloadBlob.run(peer, blob)
        end)


        Stream.run(task_stream)
    end

    handle_blobs(peer, request_number)
  end

end
