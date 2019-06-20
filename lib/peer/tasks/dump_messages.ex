defmodule Sailor.Peer.Tasks.DumpMessages do
  use Task

  require Logger
  alias Sailor.PeerConnection
  alias Sailor.Stream.Message

  @live_timeout 10*1000
  @chunk_size 1000

  # TODO: Should we use hard or soft references (via identifier)?
  def start_link(peer, history_stream_id) when is_pid(peer) do
    Task.start_link(__MODULE__, :run, [peer, history_stream_id, true])
  end

  def run(peer, history_stream_id, live? \\ false) do
    # TODO: Monitor `peer` and exit if we get the EXIT message

    stream = Sailor.Stream.for_peer(history_stream_id)

    Logger.info "Calling createHistoryStream starting at #{stream.sequence} for peer #{inspect peer}"

    args = %{
      id: history_stream_id,
      sequence: stream.sequence+1,
      live: live?,
      old: true
    }

    {:ok, request_number} = PeerConnection.rpc_stream(peer, "createHistoryStream", [args])
    message_stream(peer, history_stream_id, request_number)
    |> Stream.each(fn message -> Logger.debug "Received message #{Message.id(message)} from #{Message.author(message)}" end)
    |> Stream.chunk_every(@chunk_size)
    |> Stream.transform(stream, fn (messages, stream) ->
      {:ok, stream} = Sailor.Stream.append(stream, messages)
      :ok = Sailor.Stream.persist!(stream)
      {[], stream}
    end)
    |> Stream.run()

    if live? do
      Logger.info "Received no new message for stream #{history_stream_id} for #{@live_timeout/1000} seconds. Shutting down..."
    else
      Logger.info "Received all messages for stream #{history_stream_id}. Shutting down..."
    end
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

  def message_stream(peer, history_stream_id, request_number) do
    Stream.resource(
      fn -> nil end,
      fn _ ->
        receive do
          {:rpc_response, ^request_number, "createHistoryStream", packet} ->
            case packet_to_message(packet) do
              {:ok, message} -> {[message], nil}
              :halt -> {:halt, nil}
            end
        after
          @live_timeout ->
            Logger.info "Timeout receiving messages in #{inspect __MODULE__} for #{history_stream_id}"
            {:halt, nil}
        end
      end,
      fn _ ->
        PeerConnection.close_rpc_stream(peer, request_number)
      end
    )
  end
end
