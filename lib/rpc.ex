defmodule Sailor.Rpc do
  use GenServer
  require Logger

  def start_link([reader, writer]) do
    peer = self()
    GenServer.start_link(__MODULE__, [peer, reader, writer])
  end

  def send(rpc, name, type, args) do
    GenServer.call(rpc, {:send, name, type, args})
  end

  def init([peer, reader, writer]) do
    {:ok, {reader, writer, 1}, {:continue, peer}}
  end

  def handle_continue(peer, {reader, _writer, _request_number} = state) do
    alias Sailor.Rpc.Packet

    message_stream = Stream.resource(
      fn -> nil end,
      fn acc ->
        with <<packet_header :: binary>> <- IO.binread(reader, 9),
            #  _ = Logger.debug("Got packet header: type=#{Packet.body_type(packet_header)} body_length=#{Packet.body_length(packet_header)}"),
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

    Task.start_link(fn ->
      message_stream
      |> Stream.each(fn message -> :ok = Process.send(peer, {:rpc, message}, []) end)
      |> Stream.run()
    end)

    {:noreply, state}
  end

  def handle_call({:send, name, type, args}, _from, {reader, writer, request_number}) do
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
    |> Packet.request_number(request_number)
    |> Packet.body_type(:json)
    |> async_or_stream.()
    |> Packet.body(json)

    Logger.debug "Sending packet #{inspect Packet.info(packet)}"

    :ok = IO.write(writer, packet)
    {:reply, :ok, {reader, writer, request_number + 1}}
  end
end
