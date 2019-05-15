defmodule Sailor.Rpc do
  require Logger

  alias Sailor.Rpc.Packet

  defmodule State do
    defstruct [
      request_number: 1,
      reader: nil,
      writer: nil,
    ]
  end

  def new(reader, writer) do
    %State{
      request_number: 1,
      reader: reader,
      writer: writer,
    }
  end

  def create_packet_stream(rpc) do
    reader = rpc.reader
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
          end
        else
          _ -> {:halt, reader}
        end
      end,
      fn reader -> Process.exit(reader, :shutdown) end
    )
  end

  def send_packet(rpc, packet) do
    Logger.debug "Sending packet #{inspect Packet.info(packet)}"
    :ok = IO.write(rpc.writer, packet)
    {:ok, rpc}
  end

  def send_goodbye(rpc) do
    {:ok, rpc} = send_packet(rpc, Packet.goodbye_packet())
    {:ok, %{rpc | request_number: rpc.request_number + 1}}
  end

  def send_request(rpc, name, type, args) do
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
    |> Packet.request_number(rpc.request_number)
    |> Packet.body_type(:json)
    |> async_or_stream.()
    |> Packet.body(json)

    {:ok, rpc} = send_packet(rpc, packet)
    {:ok, %{rpc | request_number: rpc.request_number + 1}}
  end
end
