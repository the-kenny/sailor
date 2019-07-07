defmodule Sailor.Peer.Tasks.DumpFeed do
  require Logger
  alias Sailor.PeerConnection
  alias Sailor.Stream.Message

  @timeout 60_000

  def run(peer) do
    history_stream_id = PeerConnection.identifier(peer)
    run(peer, history_stream_id)
  end

  def run(peer, history_stream_id) do
    identifier = PeerConnection.identifier(peer)
    stream = Sailor.Stream.for_peer(history_stream_id)

    Logger.info "Running #{inspect __MODULE__} for #{identifier} for stream #{history_stream_id} starting at #{stream.sequence+1}"

    _ref = Process.monitor(peer)

    args = %{
      id: history_stream_id,
      sequence: stream.sequence+1,
    }

    {:ok, request_number} = PeerConnection.rpc_stream(peer, "createHistoryStream", [args])

    receive_loop(peer, request_number, stream)

    Logger.info "#{inspect __MODULE__} finished for #{identifier} for stream #{history_stream_id}"

    Sailor.MessageProcessing.Producer.notify!()
    Sailor.PeerConnection.close_rpc_stream(peer, request_number)
  end

  def receive_loop(peer, request_number, stream) do
    case receive_message(request_number, @timeout) do
      {:ok, message} ->
        {:ok, stream} = Sailor.Stream.append(stream, [message])
        receive_loop(peer, request_number, stream)

      :timeout ->
        Sailor.Stream.persist!(stream)

      :halt ->
        Sailor.Stream.persist!(stream)

      {:error, error} ->
        Logger.error "Error in #{inspect __MODULE__}: #{error}"
        Sailor.Stream.persist!(stream)
      end
    end


  def packet_to_message(packet) do
    body = Sailor.Rpc.Packet.body(packet)
    :json = Sailor.Rpc.Packet.body_type(packet)
    if Sailor.Rpc.Packet.end_or_error?(packet) do
      :halt
    else
      {:ok, message} = Message.from_history_stream_json(body)
      case Message.verify_signature(message) do
        {:error, :forged} -> Logger.warn "Couldn't verify signature of message #{Message.id(message)}"
        :ok -> :ok
      end
      {:ok, message}
    end
  end

  defp receive_message(request_number, timeout) do
    receive do
      {:DOWN, _ref, :process, _object, _reason} ->
        {:error, "Peer shut down"}

      {:rpc_response, ^request_number, "createHistoryStream", packet} ->
        case packet_to_message(packet) do
          {:ok, message} -> {:ok, message}
          :halt -> :halt
        end
    after
      timeout -> :timeout
    end
  end
end
