defmodule Sailor.Peer.Tasks.DumpMessages do
  use Task

  require Logger
  alias Sailor.PeerConnection

  # TODO: Should we use hard or soft references (via identifier)?
  def start_link(peer_identifier, history_stream_id) do
    Task.start_link(__MODULE__, :run, [peer_identifier, history_stream_id])
  end

  def start_link(peer_identifier) do
    start_link(peer_identifier, peer_identifier)
  end

  def run(peer_identifier, history_stream_id) do
    peer = PeerConnection.for_identifier(peer_identifier)
    {:ok, request_number} = PeerConnection.rpc_stream(peer, "createHistoryStream", [%{id: history_stream_id}])
    recv_message(peer_identifier, request_number)
  end

  defp recv_message(peer_identifier, request_number) do
    receive do
      {:rpc_response, ^request_number, "createHistoryStream", packet} ->
        body = Sailor.Rpc.Packet.body(packet)
        :json = Sailor.Rpc.Packet.body_type(packet)
        if !Sailor.Rpc.Packet.end_or_error?(packet) do
          {:ok, message} = Sailor.Message.from_history_stream_json(body)
          case Sailor.Message.verify_signature(message) do
            {:error, :forged} -> Logger.warn "Couldn't verify authenticity of message #{Sailor.Message.id(message)}"
            :ok -> :ok
          end
          :ok = Sailor.Gossip.Store.store(message)
          recv_message(peer_identifier, request_number)
        else
          Logger.info "DumpMessages finished for #{peer_identifier}"
        end
    after
      5000 -> Logger.warn "Timeout receiving messages in #{inspect __MODULE__} for #{peer_identifier}"
    end
  end
end
