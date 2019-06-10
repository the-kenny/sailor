defmodule Sailor.Peer.Tasks.DumpMessages do
  use Task

  require Logger
  alias Sailor.PeerConnection

  @live_timeout 5*60*1000

  # TODO: Should we use hard or soft references (via identifier)?
  def start_link(peer, history_stream_id) when is_pid(peer) do
    Task.start_link(__MODULE__, :run, [peer, history_stream_id])
  end

  def run(peer, history_stream_id) do
    Process.link(peer)

    {:ok, seq} = Memento.transaction fn ->
      Memento.Query.select(Sailor.Message, [{:==, :author, history_stream_id}])
      |> Stream.map(&Sailor.Message.sequence/1)
      |> Enum.max(fn -> 0 end)
    end

    Logger.info "Calling createHistoryStream starting at #{seq} for peer #{inspect peer}"

    args = %{
      id: history_stream_id,
      sequence: seq,
      live: true,
      old: true
    }

    {:ok, request_number} = PeerConnection.rpc_stream(peer, "createHistoryStream", [args])
    recv_message(peer, history_stream_id, request_number)
  end

  defp recv_message(peer, history_stream_id, request_number) do
    receive do
      {:rpc_response, ^request_number, "createHistoryStream", packet} ->
        body = Sailor.Rpc.Packet.body(packet)
        :json = Sailor.Rpc.Packet.body_type(packet)
        if !Sailor.Rpc.Packet.end_or_error?(packet) do
          {:ok, message} = Sailor.Message.from_history_stream_json(body)
          case Sailor.Message.verify_signature(message) do
            {:error, :forged} -> Logger.warn "Couldn't verify signature of message #{Sailor.Message.id(message)}"
            :ok -> :ok
          end
          Memento.transaction! fn ->
            Memento.Query.write(message)
          end

          recv_message(peer, history_stream_id, request_number)
        else
        end
      after
        @live_timeout ->
          Logger.info "Timeout receiving messages in #{inspect __MODULE__} for #{history_stream_id}"
          :ok = PeerConnection.close_rpc_stream(peer, request_number)
          Logger.info "Received no new message for stream #{history_stream_id} for #{@live_timeout} seconds. Shutting down..."
      end
  end
end
