defmodule Sailor.Peer.Tasks.DumpFeed do
  require Logger
  alias Sailor.PeerConnection
  alias Sailor.Stream.Message

  @default_live_timeout 10*1000
  @chunk_size 1000

  def run(peer), do: run(peer, @default_live_timeout)

  def run(peer, timeout) do
    history_stream_id = PeerConnection.identifier(peer)
    run(peer, history_stream_id, timeout)
  end

  def run(peer, history_stream_id, timeout) do
    Logger.info "Running #{inspect __MODULE__} for #{PeerConnection.identifier(peer)} for stream #{history_stream_id} with timeout of #{timeout}"

    _ref = Process.monitor(peer)

    stream = Sailor.Stream.for_peer(history_stream_id)

    args = %{
      id: history_stream_id,
      sequence: stream.sequence+1,
      live: true,
      old: true
    }

    {:ok, request_number} = PeerConnection.rpc_stream(peer, "createHistoryStream", [args])
    message_stream(peer, history_stream_id, request_number, timeout)
    |> Stream.each(fn message -> Logger.debug "Received message #{Message.id(message)} from #{Message.author(message)}" end)
    |> Stream.chunk_every(@chunk_size)
    |> Stream.transform(stream, fn (messages, stream) ->
      {:ok, stream} = Sailor.Stream.append(stream, messages)
      :ok = Sailor.Stream.persist!(stream)
      {[], stream}
    end)
    |> Stream.run()

    Logger.info "Received no new message for stream #{history_stream_id}. Shutting down..."
  end

  def packet_to_message(packet) do
    body = Sailor.Rpc.Packet.body(packet)
    :json = Sailor.Rpc.Packet.body_type(packet)
    if !Sailor.Rpc.Packet.end_or_error?(packet) do
      {:ok, message} = Message.from_history_stream_json(body)
      case Message.verify_signature(message) do
        {:error, :forged} -> Logger.warn "Couldn't verify signature of message #{Message.id(message)}"
        :ok -> :ok
      end
      {:ok, message}
    else
      :halt
    end
  end

  def message_stream(peer, _history_stream_id, request_number, timeout) do
    Stream.resource(
      fn -> nil end,
      fn _ ->
        receive do
          {:DOWN, _ref, :process, _object, _reason} ->
            {:halt, nil}

          {:rpc_response, ^request_number, "createHistoryStream", packet} ->
            case packet_to_message(packet) do
              {:ok, message} -> {[message], nil}
              :halt -> {:halt, nil}
            end
        after
          timeout ->
            PeerConnection.close_rpc_stream(peer, request_number)
            {:halt, nil}
        end
      end,
      fn _ -> nil end
    )
  end
end
