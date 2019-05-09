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

  def handle_call({:send, name, type, args}, from, {reader, writer, request_number}) do
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

  # defprotocol Handler do
    #   def handle_
    # end

    defmodule Packet do
    # @spec parse(binary()) :: {:ok, struct(), binary()} | :incomplete | {:incomplete, integer()} | {:error, :invalid}

    # def parse(binary) when byte_size(binary) < 9 do
    #   :incomplete
    # end

    # def parse(<<header :: binary-9, body :: binary>> = packet) do
    #   cond
    #    body_length(packet) < byte_size(body) -> {:incomplete, body_length(packet) - byte_size(body)}
    #    valid?(packet) -> {:ok}
    #   else
    #     valid?(packet)
    #   end
    # end

    defmacro packet_binary do
      quote generated: true do
        <<
        0 :: 4,
        var!(stream?) :: 1,
        var!(end_or_error?) :: 1,
        var!(body_type) :: 2,
        var!(body_length) :: unsigned-32,
        var!(request_number) :: signed-32,
        var!(body) :: binary,
      >>
      end
    end

    @doc """
    Creates an empty packet with all flags set to zero, packet number 0 and body length 0
    ## Examples

      iex> create() |> body_length()
      0
    """
    def create() do
      stream? = 0
      end_or_error? = 0
      body_type = 0
      body_length = 0
      request_number = 0
      body = <<>>
      packet_binary()
    end

    @doc """
    ## Examples

      iex> create() |> stream() |> stream?()
      true
    """
    def stream(packet) do
      packet_binary() = packet
      stream? = 1
      packet_binary()
    end

    def async(packet) do
      packet_binary() = packet
      stream? = 0
      packet_binary()
    end

    def stream?(packet) do
      packet_binary() = packet
      stream? == 1
    end

    def request_number(packet, new_request_number) do
      packet_binary() = packet
      request_number = new_request_number
      packet_binary()
    end

    def request_number(packet) do
      packet_binary() = packet
      request_number
    end

    def body_type(packet) do
      packet_binary() = packet
      case body_type do
        0 -> :binary
        1 -> :utf8
        2 -> :json
      end
    end

    def body_type(packet, new_body_type) do
      packet_binary() = packet
      body_type = case new_body_type do
        :binary -> 0
        :utf8 -> 1
        :json -> 2
      end
      packet_binary()
    end

    def end_or_error?(packet) do
      packet_binary() = packet
      end_or_error? == 1
    end


    def body_length(packet) do
      packet_binary() = packet
      body_length
    end

    def body(packet) do
      packet_binary() = packet
      body
    end

    def body(packet, new_body) do
      packet_binary() = packet
      body_length = byte_size(new_body)
      body = new_body
      packet_binary()
    end

    @doc """
    Hello world.

    ## Examples

        iex> packet = create() |> stream() |> request_number(42) |> body_type(:utf8) |> body("HELLO")
        iex> info(packet)
        {42, :stream, false, :utf8, 5, "HELLO"}

    """
    def info(packet) do
      packet_binary() = packet

      body_type = case body_type do
        0 -> :binary
        1 -> :utf8
        2 -> :json
      end

      {
        request_number,
        (if stream? == 1, do: :stream, else: :async),
        end_or_error? == 1,
        body_type,
        body_length,
        body
      }
    end
  end
end
