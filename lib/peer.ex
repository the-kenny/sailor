defmodule Sailor.Peer do
  use GenServer, restart: :temporary

  require Logger

  alias Sailor.Keypair
  alias Sailor.Rpc.Packet

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
  def handle_rpc_request(packet, state) do
    request_number = Packet.request_number(packet)

    if Packet.body_type(packet) != :json do
      Logger.warn "Unknown RPC message #{request_number} of type: #{inspect Packet.body_type(packet)}: #{inspect Packet.body(packet)}"
      {:noreply, state}
    else
      {:ok, %{"name" => name, "type" => type, "args" => args}} = Jason.decode(Packet.body(packet))

      # This check has a race condition, but we only use it for logging. Nothing to worry about.
      if Registry.lookup(Sailor.Rpc.HandlerRegistry, name) == [] do
        Logger.warn "No handler found for #{inspect name}, we MAY not be able to answer request #{request_number}"
      end

      Registry.dispatch(Sailor.Rpc.HandlerRegistry, name, fn handlers ->
        Enum.each(handlers, fn {_pid, handler} ->
          Process.send(handler, {:rpc_request, name, type, args, packet, state.rpc}, [])
        end)
      end)
      {:noreply, state}
    end
  end

  def handle_rpc_response(packet, state) do
    packet = Packet.info(packet)
    Logger.info "Received RPC response to #{-packet.request_number}: #{inspect packet.body}"
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

    {:ok, rpc} = Sailor.Rpc.subscribe_link([reader, writer])

    :ok = Sailor.Rpc.call(rpc, ["createHistoryStream"], :source, [%{id: state.identifier, live: true, old: true}])
    :ok = Sailor.Rpc.call(rpc, ["blobs", "has"], :async, ["&F9tH7Ci4f1AVK45S9YhV+tK0tsmkTjQLSe5kQ6nEAuo=.sha256"])

    {:noreply, %{state | rpc: rpc}}
  end

  def handle_info({:rpc, rpc_packet}, state) do
    case Packet.request_number(rpc_packet) do
      n when n < 0 ->
        Logger.debug "Dispatching rpc response #{-n}: #{inspect rpc_packet}"
        handle_rpc_response(rpc_packet, state)
      n when n > 0 ->
        Logger.debug "Dispatching rpc request #{n}: #{inspect rpc_packet}"
        handle_rpc_request(rpc_packet, state)
    end
  end

  # Shutdown Handling

  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  def terminate(reason, state) do
    Logger.info "Shutting down node #{state.identifier} with reason #{inspect reason}"
  end
end
