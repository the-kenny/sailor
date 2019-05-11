defmodule Sailor.Peer do
  use GenServer

  require Logger

  alias Sailor.Keypair

  defmodule State do
    defstruct [
      identifier: nil,
      keypair: nil,
    ]
  end

  def start_link({socket, handshake}) do
    GenServer.start_link(__MODULE__, [socket, handshake])
  end

  def handle_rpc_request(packet_number, _type, msg, state) do
    Logger.warn "Unhandled RPC request ##{packet_number}: #{inspect msg}"
    {:noreply, state}
  end

  def handle_rpc_response(packet_number, _type, msg, state) do
    Logger.info "Received RPC response to #{-packet_number}: #{inspect msg}"
    {:noreply, state}
  end

  # Callbacks

  def init([socket, handshake]) do
    other = Keypair.from_pubkey(handshake.other_pubkey)
    state = %State{
      keypair: other,
      identifier: Keypair.id(other),
    }
    {:ok, state, {:continue, {:initialize, handshake, socket}}}
  end

  def handle_continue({:initialize, handshake, socket}, state) do
    Logger.info "Connected with peer #{inspect state.identifier}"
    # TODO: open this in RPC
    {:ok, reader, writer} = Sailor.Boxstream.IO.open(socket, handshake)
    {:ok, rpc} = Sailor.Rpc.start_link([reader, writer])

    :ok = Sailor.Rpc.send(rpc, ["createHistoryStream"], :source, [%{id: state.identifier, live: true, old: true}])
    :ok = Sailor.Rpc.send(rpc, ["blobs", "has"], :async, ["&F9tH7Ci4f1AVK45S9YhV+tK0tsmkTjQLSe5kQ6nEAuo=.sha256"])

    {:noreply, state}
  end

  def handle_info({:rpc, {packet_number, type, msg}}, state) when packet_number < 0 do
    handle_rpc_response(packet_number, type, msg, state)
  end

  def handle_info({:rpc, {packet_number, type, msg}}, state) when packet_number > 0 do
    handle_rpc_request(packet_number, type, msg, state)
  end

end
