defmodule Sailor.Peer.Tasks.FetchGossip do
  require Logger

  def run(peer_connection) do
    peer = Sailor.Peer.for_identifier(Sailor.PeerConnection.identifier(peer_connection))

    streams = [peer.identifier] ++ MapSet.to_list(peer.contacts)

    task = fn identifier ->
      Sailor.Peer.Tasks.FetchGossip.SingleFeed.run(peer_connection, identifier)
    end

    persist_stream = fn arg ->
      case arg do
        {:ok, stream} -> Sailor.Stream.persist!(stream)
        {:error, err} -> Logger.warn "Failed to fetch stream: #{err}"
      end
    end

    Task.Supervisor.async_stream_nolink(Sailor.Peer.TaskSupervisor, streams, task, max_concurrency: 5, ordered: false, timeout: :infinity)
    |> Stream.each(persist_stream)
    |> Stream.run()

    Sailor.MessageProcessing.Producer.notify!()
  end
end

defmodule Sailor.Peer.Tasks.FetchGossip.SingleFeed do
  require Logger
  alias Sailor.PeerConnection
  alias Sailor.Stream.Message

  @timeout 3_000

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

    {:ok, stream} = receive_loop(peer, request_number, stream)

    Logger.info "#{inspect __MODULE__} finished for #{identifier} for stream #{history_stream_id}"

    Sailor.PeerConnection.close_rpc_stream(peer, request_number)

    stream
  end

  def receive_loop(peer, request_number, stream) do
    case receive_message(request_number, @timeout) do
      {:ok, message} ->
        {:ok, stream} = Sailor.Stream.append(stream, [message])
        receive_loop(peer, request_number, stream)

      :timeout ->
        {:ok, stream}

      :halt ->
        {:ok, stream}

      {:error, error} ->
        Logger.error "Error in #{inspect __MODULE__}: #{error}"
        {:ok, stream}
      end
    end


  @spec packet_to_message(binary()) :: {:ok, %Message{}} | :halt
  def packet_to_message(packet) do
    body = Sailor.Rpc.Packet.body(packet)
    :json = Sailor.Rpc.Packet.body_type(packet)
    if Sailor.Rpc.Packet.end_or_error?(packet) do
      :halt
    else
      {:ok, message} = Message.from_history_stream_json(body)
      # case Message.verify_signature(message) do
      #   {:error, :forged} -> Logger.warn "Couldn't verify signature of message #{Message.id(message)}"
      #   :ok -> nil
      # end
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
