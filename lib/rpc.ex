defmodule Sailor.Rpc do
  use GenServer
  require Logger

  alias Sailor.Rpc.Packet

  defmodule State do
    defstruct [
      request_number: 1,
      reader: nil,
      writer: nil,
    ]
  end

  def subscribe([reader, writer]) do
    peer = self()
    GenServer.start(__MODULE__, [peer, reader, writer])
  end

  def subscribe_link([reader, writer]) do
    peer = self()
    GenServer.start_link(__MODULE__, [peer, reader, writer])
  end

  def call(rpc, name, type, args) do
    GenServer.call(rpc, {:send, name, type, args})
  end

  def respond(rpc, packet) do
    GenServer.call(rpc, {:respond, packet})
  end

  def send_goodbye(rpc) do
    GenServer.call(rpc, :goodbye)
  end

  defp create_packet_stream(reader) do
    Stream.resource(
      fn -> reader end,
      fn reader ->
        with <<packet_header :: binary>> <- IO.binread(reader, 9),
             content_length = Packet.body_length(packet_header),
             <<packet_body :: binary>> <- IO.binread(reader, content_length),
             packet = packet_header <> packet_body
        do
          if Packet.goodbye_packet?(packet) do
            Logger.debug "Received RPC GOODBYE packet"
            {:halt, reader}
          else
            Logger.debug "Received RPC packet: #{inspect Packet.info(packet)}"
            {[packet], reader}
            # request_number = Packet.request_number(packet)
            # stream_or_async = case Packet.stream?(packet) do
            #   true -> :stream
            #   false -> :async
            # end
            # body_type = Packet.body_type(packet)
            # body = case body_type do
            #   :binary -> Packet.body(packet)
            #   :utf8   -> Packet.body(packet)
            #   :json   -> Jason.decode!(Packet.body(packet))
            # end

            # message = {request_number, stream_or_async, body_type, body}

            # {[message], reader}
          end
        else
          _ -> {:halt, reader}
        end
      end,
      fn reader -> Process.exit(reader, :shutdown) end
    )
  end

  defp send_packet(packet, state) do
    Logger.debug "Sending packet #{inspect Packet.info(packet)}"
    :ok = IO.write(state.writer, packet)
  end

  # Callbacks

  def init([peer, reader, writer]) do
    Process.flag(:trap_exit, true)

    state = %State{
      request_number: 1,
      reader: reader,
      writer: writer,
    }
    {:ok, state, {:continue, {:start_stream, peer}}}
  end

  def handle_continue({:start_stream, peer}, state) do
    packet_stream = create_packet_stream(state.reader)

    # Start a task reading all messages from `state.reader` and pass them on to our parent `peer`
    {:ok, _reader_task} = Task.start_link(fn ->
      packet_stream
      |> Stream.each(fn packet -> :ok = Process.send(peer, {:rpc, packet}, []) end)
      |> Stream.run()

      Logger.debug "RPC stream for #{inspect self()} closed. Shutting down..."

      Process.exit(self(), :shutdown)
    end)

    {:noreply, state}
  end


  def handle_call({:send, name, type, args}, _from, state) do
    {:ok, json} = Jason.encode %{
      name: name,
      type: type,
      args: args,
    }

    async_or_stream = fn packet ->
      case type do
        :async -> Packet.async(packet)
        :source -> Packet.stream(packet)
      end
    end

    packet = Packet.create()
    |> Packet.request_number(state.request_number)
    |> Packet.body_type(:json)
    |> async_or_stream.()
    |> Packet.body(json)

    :ok = send_packet(packet, state)
    {:reply, :ok, %{state | request_number: state.request_number + 1}}
  end

  def handle_call({:respond, packet}, _from, state) do
    :ok = send_packet(packet, state)
    {:reply, :ok, state}
  end

  def handle_call(:goodbye, _from, state) do
    send_packet(Packet.goodbye_packet(), state)
    # TODO: Should we shut ourself down?
    {:reply, :ok, %{state | request_number: state.request_number + 1}}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.debug "Shutting down RPC because subprocess #{inspect pid} stopped. Reason: #{inspect reason}"
    {:stop, reason, state}
  end
end
