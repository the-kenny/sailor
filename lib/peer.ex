defmodule Sailor.Peer do
  use GenServer, restart: :temporary

  require Logger

  alias Sailor.Keypair

  defmodule State do
    defstruct [
      identifier: nil,
      keypair: nil,
      rpc: nil,
    ]
  end

  def start_link({socket, handshake}) do
    GenServer.start_link(__MODULE__, [socket, handshake])
  end

  # TODO: Move this logic to somewhere else (`Sailor.Rpc.HandlerRegistry`?)
  def handle_rpc_request(packet_number, :json, %{"name" => name, "type" => type, "args" => args}, state) do
    # This check has a race condition, but we only use it for logging. Nothing to worry about.
    if Registry.lookup(Sailor.Rpc.HandlerRegistry, name) == [] do
      Logger.warn "No handler found for #{inspect name}, we MAY not be able to answer request #{packet_number}"
    end

    me = self()
    Registry.dispatch(Sailor.Rpc.HandlerRegistry, name, fn handlers ->
      Enum.each(handlers, fn {_pid, handler} ->
        Sailor.Rpc.Handler.call(handler, name, type, args, me)
      end)
    end)
    {:noreply, state}
  end

  def handle_rpc_request(packet_number, type, msg, state) do
    Logger.warn "Unknown RPC message #{packet_number} of type: #{inspect type}: #{inspect msg}"
    {:noreply, state}
  end

  def handle_rpc_response(packet_number, _type, msg, state) do
    Logger.info "Received RPC response to #{-packet_number}: #{inspect msg}"
    {:noreply, state}
  end

  # Callbacks

  def init([socket, handshake]) do
    Process.flag(:trap_exit, true)

    other = Keypair.from_pubkey(handshake.other_pubkey)
    state = %State{
      keypair: other,
      identifier: Keypair.id(other),
    }
    {:ok, state, {:continue, {:initialize, handshake, socket}}}
  end

  def handle_continue({:initialize, handshake, socket}, state) do
    Logger.info "Initializing RPC for peer #{inspect state.identifier}"
    # TODO: open this in RPC
    {:ok, reader, writer} = Sailor.Boxstream.IO.open(socket, handshake)

    {:ok, rpc} = Sailor.Rpc.start_link([reader, writer])

    :ok = Sailor.Rpc.send(rpc, ["createHistoryStream"], :source, [%{id: state.identifier, live: true, old: true}])
    :ok = Sailor.Rpc.send(rpc, ["blobs", "has"], :async, ["&F9tH7Ci4f1AVK45S9YhV+tK0tsmkTjQLSe5kQ6nEAuo=.sha256"])

    {:noreply, %{state | rpc: rpc}}
  end

  def handle_info({:rpc, {packet_number, type, msg}}, state) when packet_number < 0 do
    handle_rpc_response(packet_number, type, msg, state)
  end

  def handle_info({:rpc, {packet_number, type, msg}}, state) when packet_number > 0 do
    Logger.debug "Dispatching rpc request #{packet_number}: #{inspect msg}"
    handle_rpc_request(packet_number, type, msg, state)
  end

  # Shutdown Handling

  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  def terminate(reason, state) do
    Logger.info "Shutting down node #{state.identifier} with reason #{inspect reason}"
  end
end
