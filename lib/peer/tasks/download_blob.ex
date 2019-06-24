defmodule Sailor.Peer.Tasks.DownloadBlob do
  require Logger
  alias Sailor.PeerConnection
  alias Sailor.Rpc.Packet
  alias Sailor.Blob

  def run(peer, blob_id) do
    {:ok, _request_number} = PeerConnection.rpc_stream(peer, ["blobs", "get"], [ blob_id ])

    temp_path = Path.join([System.tmp_dir!(), "tmp_blob_#{:erlang.phash2(make_ref())}"])
    Logger.info "Starting to stream data for blob #{blob_id} into #{temp_path}"
    recv_slice(peer, blob_id, temp_path);
  end

  def recv_slice(peer, blob_id, temp_path) do
    receive do
      {:rpc_response, _request_number, ["blobs", "get"], packet} ->
        case Packet.body_type(packet) do
          :json ->
            {:ok, blob} = Blob.from_file(temp_path)
            if blob != blob_id do
              raise "Blob #{blob_id} at #{temp_path} failed hash-check (got #{blob})"
            end
            :ok = Blob.persist_file!(temp_path)
            Blob.remove_wanted!(blob)
            Logger.info "Successfully downloaded blob #{blob}"
          :binary ->
            File.write!(temp_path, Packet.body(packet), [:append, :binary])
            recv_slice(peer, blob_id, temp_path)
        end
      end
  end

end
