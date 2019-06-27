defmodule Sailor.PeerConnection do
  use GenServer, restart: :temporary

  require Logger

  alias Sailor.Keypair
  alias Sailor.Rpc.Packet

  defmodule State do
    defstruct [
      identifier: nil,
      keypair: nil,
      rpc: nil,
      socket: nil,

      pending_calls: %{}, # maps from request-id to `{rpc-name, from}` tuple to respond to the call
    ]
  end

  # TODO: We should run the whole connection process in `init` (and handle the registration for `start_incoming` there as it would prevent connecting to a peer twice
  def start_incoming(socket, local_identity, network_identifier) do
    with {:ok, handshake} <- Sailor.PeerConnection.Handshake.incoming(socket, local_identity, network_identifier),
         {:ok, peer} <- DynamicSupervisor.start_child(Sailor.PeerConnectionSupervisor, {Sailor.PeerConnection, {socket, handshake}}),
    do: {:ok, peer}
  end

  def start_outgoing(ip, port, other_identity, local_identity, network_identifier) do
    with {:ok, socket, handshake} <- Sailor.PeerConnection.Handshake.outgoing({ip, port, other_identity.pub}, local_identity, network_identifier),
         {:ok, peer} <- DynamicSupervisor.start_child(Sailor.PeerConnectionSupervisor, {Sailor.PeerConnection, {socket, handshake}}),
    do: {:ok, peer}
  end

  def start_link({socket, handshake}, register? \\ true) do
    identifier = handshake.other_pubkey |> Keypair.from_pubkey() |> Keypair.identifier()
    name = if register?, do: via_tuple(identifier), else: nil
    GenServer.start_link(__MODULE__, [socket, handshake], name: name)
  end

  def stop(peer) do
    GenServer.cast(peer, :shutdown)
  end

  defp via_tuple(identifier) do
    {:via, Registry, {Sailor.PeerConnection.Registry, identifier}}
  end

  def for_identifier(identifier) do
    via_tuple(identifier)
  end

  def identifier(peer) do
    GenServer.call(peer, :identifier)
  end

  def send_rpc_response(peer, packet) do
    GenServer.call(peer, {:send_rpc_response, packet})
  end

  def rpc_call(peer, name, args, timeout \\ 5000) do
    GenServer.call(peer, {:rpc_call, :async, name, args}, timeout)
  end

  def rpc_stream(peer, name, args) do
    GenServer.call(peer, {:rpc_call, :source, name, args})
  end

  def close_rpc_stream(peer, request_number) do
    GenServer.call(peer, {:close_rpc_source, request_number})
  end

  # Private Methods

  # TODO: Move this logic to somewhere else (`Sailor.Rpc.HandlerRegistry`?)
  defp handle_rpc_request(packet, state) do
    request_number = Packet.request_number(packet)

    case Packet.rpc_call(packet) do
      nil ->
        Logger.warn "Unknown RPC message #{request_number} of type: #{inspect Packet.body_type(packet)}: #{inspect Packet.body(packet)}"
      call ->
        dispatch_rpc_call(call)
    end

    {:ok, state}
  end

  defp dispatch_rpc_call(call) do
    case Sailor.Rpc.HandlerRegistry.dispatch_async(self(), call) do
      :ok -> :ok
      {:error, error} -> Logger.warn "Couldn't handle RPC request: #{inspect call.name}: #{error}"
    end
  end

  defp handle_rpc_response(packet, state) do
    request_number = -Packet.request_number(packet)
    stream? = Packet.stream?(packet)
    end_or_error? = Packet.end_or_error?(packet)

    if Map.has_key?(state.pending_calls, request_number) do
      # If it's a stream we're sending the data as normal messages.
      # If not, the caller is still waiting for a response to its
      # `GenServer.call` and we have to reply with `GenServer.reply`
      if stream? do
        # If this match fails we're receiving a `stream` response to an `async` rpc call (is this allowed?)
        {rpc_name, {:source, receiver}} = Map.get(state.pending_calls, request_number)
        :ok = Process.send(receiver, {:rpc_response, request_number, rpc_name, packet}, [])
      else
        {rpc_name, {:async, receiver}} = Map.get(state.pending_calls, request_number)
        :ok = GenServer.reply(receiver, {:ok, request_number, rpc_name, packet})
      end

      # This RPC call is finished when either it's not a stream, or it's a stream and the `end_or_error?` flag is set
      state = case {stream?, end_or_error?} do
        {false, _} -> remove_receiver(state, request_number)
        {true, true} -> remove_receiver(state, request_number)
        {true, false} -> state
      end

      {:ok, state}
    else
      Logger.warn "Received RPC response for unknown request with id #{Packet.request_number(packet)}"
      {:ok, state}
    end
  end

  defp add_receiver(state, request_number, rpc_name, receiver) do
    %{ state | pending_calls: Map.put(state.pending_calls, request_number, {rpc_name, receiver}) }
  end

  defp remove_receiver(state, request_number) do
    %{ state | pending_calls: Map.delete(state.pending_calls, request_number) }
  end

  # Callbacks

  def init([socket, handshake]) do
    other_keypair = Keypair.from_pubkey(handshake.other_pubkey)
    identifier = Keypair.identifier(other_keypair)

    Logger.info "Started Peer process for #{identifier}"

    Process.flag(:trap_exit, true)

    state = %State{
      keypair: other_keypair,
      identifier: identifier,
    }
    {:ok, state, {:continue, {:initialize, handshake, socket}}}
  end

  def handle_continue({:initialize, handshake, socket}, state) do
    Logger.debug "Initializing RPC for peer #{inspect state.identifier}"
    # TODO: open this in RPC
    {:ok, reader, writer} = Sailor.Boxstream.IO.open(socket, handshake)

    # TODO: mov to helper function
    rpc = Sailor.Rpc.new(reader, writer)
    me = self()
    Task.start_link(fn ->
      rpc
      |> Sailor.Rpc.create_packet_stream()
      |> Stream.each(fn packet -> :ok = Process.send(me, {:rpc, packet}, []) end)
      |> Stream.run()

      Logger.debug "RPC stream for #{state.identifier} closed."

      stop(me)
    end)

    tasks = Application.get_env(:sailor, __MODULE__) |> Keyword.get(:tasks, [])
    peer = self()

    for {module, args} <- tasks do
      Task.Supervisor.start_child(Sailor.Peer.TaskSupervisor, module, :run, [peer] ++ args)
    end

    {:noreply, %{state | socket: socket, rpc: rpc}}
  end

  def handle_cast(:shutdown, state) do
    {:stop, :normal, state}
  end

  def handle_call(:identifier, _from, state) do
    {:reply, state.identifier, state}
  end

  def handle_call({:send_rpc_response, packet}, _from, state) do
    {:ok, rpc} = Sailor.Rpc.send_packet(state.rpc, packet)
    {:reply, :ok, %{state | rpc: rpc}}
  end

  def handle_call({:rpc_call, :async, name, args}, from, state) do
    {:ok, request_number, rpc} = Sailor.Rpc.send_request(state.rpc, name, :async, args)
    state = %{state | rpc: rpc } |> add_receiver(request_number, name, {:async, from})
    {:noreply, state}
  end

  def handle_call({:rpc_call, :source, name, args}, {from_pid, _}, state) do
    {:ok, request_number, rpc} = Sailor.Rpc.send_request(state.rpc, name, :source, args)
    state = %{state | rpc: rpc } |> add_receiver(request_number, name, {:source, from_pid})
    {:reply, {:ok, request_number}, state}
  end

  def handle_call({:close_rpc_source, request_number}, _from, state) do
    packet = Sailor.Rpc.Packet.create()
    |> Sailor.Rpc.Packet.request_number(request_number)
    |> Sailor.Rpc.Packet.stream()
    |> Sailor.Rpc.Packet.end_or_error()
    |> Sailor.Rpc.Packet.body_type(:json)
    |> Sailor.Rpc.Packet.body("true")

    {:ok, rpc} = Sailor.Rpc.send_packet(state.rpc, packet)
    state = %{state | rpc: rpc }
    {:reply, :ok, state}
  end

  def handle_info({:rpc, rpc_packet}, state) do
    {:ok, state} = case Packet.request_number(rpc_packet) do
      n when n < 0 ->
        # Logger.debug "Dispatching rpc response #{-n}: #{inspect rpc_packet}"
        handle_rpc_response(rpc_packet, state)
      n when n > 0 ->
        # Logger.debug "Dispatching rpc request #{n}: #{inspect Packet.body(rpc_packet)}"
        handle_rpc_request(rpc_packet, state)
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  def terminate(reason, state) do
    Logger.info "Shutting down node #{state.identifier} with reason #{inspect reason}"
    {:ok, _rpc} = Sailor.Rpc.send_goodbye(state.rpc)
    :ok = :gen_tcp.close(state.socket)
  end
end
