defmodule Sailor.Rpc do
  use GenServer
  require Logger

  alias Sailor.Rpc.Packet


  defmodule State do
    defstruct [
      request_number: 1,
      reader: nil,
      writer: nil,
      response_registry: nil, # Maps from `request_id` to a process
    ]
  end

  def start_link([reader, writer]) do
    peer = self()
    GenServer.start_link(__MODULE__, [peer, reader, writer])
  end

  def send(rpc, name, type, args) do
    GenServer.call(rpc, {:send, name, type, args})
  end

  def create_message_stream(reader) do
    Stream.resource(
      fn -> nil end,
      fn acc ->
        with <<packet_header :: binary>> <- IO.binread(reader, 9),
             content_length = Packet.body_length(packet_header),
             <<packet_body :: binary>> <- IO.binread(reader, content_length),
             packet = packet_header <> packet_body
        do
          request_number = Packet.request_number(packet)
          body_type = Packet.body_type(packet)
          body = case body_type do
            :binary -> Packet.body(packet)
            :utf8   -> Packet.body(packet)
            :json   -> Jason.decode!(Packet.body(packet))
          end
          {[{request_number, body_type, body}], acc}
        else
          _ -> {:halt, acc}
        end
      end,
      fn _acc -> Process.exit(self(), :boxstream_closed) end
    )
  end

  # Callbacks

  def init([peer, reader, writer]) do
    state = %State{
      request_number: 1,
      reader: reader,
      writer: writer,
      response_registry: Registry.start_link(keys: :unique, name: Sailor.Rpc.ResponseHandlerRegistry),
    }
    {:ok, state, {:continue, peer}}
  end

  def handle_continue(peer, state) do
    message_stream = create_message_stream(state.reader)

    # Start a task reading all messages from `state.reader` and pass them on to our parent `peer`
    Task.start_link(fn ->
      message_stream
      |> Stream.each(fn message -> Logger.debug "Received RPC message: #{inspect message}" end)
      |> Stream.each(fn message -> :ok = Process.send(peer, {:rpc, message}, []) end)
      |> Stream.run()
    end)

    {:noreply, state}
  end

  def handle_call({:send, name, type, args}, _from, state) do
    alias Sailor.Rpc.Packet

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

    Logger.debug "Sending packet #{inspect Packet.info(packet)}"

    :ok = IO.write(state.writer, packet)
    {:reply, :ok, %{state | request_number: state.request_number + 1}}
  end
end
