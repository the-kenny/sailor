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

  def handle_info({:rpc, {packet_number, _type, msg}}, state) when packet_number < 0 do
    Logger.info "Received RPC response #{inspect packet_number}: #{inspect msg}"
    {:noreply, state}
  end

  def handle_info({:rpc, {packet_number, _type, msg}}, state) when packet_number > 0 do
    Logger.warn "Unhandled RPC request: #{inspect msg}"
    {:noreply, state}
  end

end
