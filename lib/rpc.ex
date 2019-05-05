defmodule Sailor.Rpc do
  use GenServer

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


    @doc """
    Hello world.

    ## Examples

        iex> packet = Sailor.Rpc.Packet.stream(42, :utf8, "HELLO")
        iex> Sailor.Rpc.Packet.info(packet)
        {42, :stream, false, :utf8, 5}

    """
    def info(<<header :: binary-9, _body :: binary>>) do
      <<
        0 :: 4,
        stream? :: 1,
        end_or_error? :: 1,
        body_type :: 2,
        body_length :: unsigned-32,
        request_number :: signed-32,
      >> = header

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
      }
    end

    # TODO: Write a fluent API to create packets

    def stream(request_number, content_type, body) do
      content_type = case content_type do
        :binary -> <<0, 0>>
        :utf8 ->   <<0, 1>>
        :json ->   <<1, 0>>
      end |> :binary.decode_unsigned
      <<
        0 :: 4,
        1 :: 1, # This is a stream
        0 :: 1, # This is not an end or error
        content_type :: 2,
        byte_size(body) :: 32,
        request_number :: signed-32,
        body :: binary
      >>
    end

    # TODO: Reimplement all following in terms of `Packet.info`

    def body_length(packet) do
      <<_flags :: 8, body_length :: integer-32, _request_number :: 32, _body :: binary>> = packet
      body_length
    end

    def request_number(packet) do
      <<_flags :: 8, _body_length :: 32, request_number :: signed-integer-32, _body :: binary>> = packet
      request_number
    end

    # defmacro header() do
    #   quote do: <<
    #     0 :: 4,
    #     var!(stream?) :: 1,
    #     var!(end_or_error?) :: 1,
    #     var!(body_type) :: 2,
    #     var!(body_length) :: integer-32,
    #     var!(request_number) :: integer-32
    #   >>
    # end

    def end_or_error?(packet) do
      {_, end_or_error?, _} = flags(packet)
      end_or_error?
    end

    def stream?(packet) do
      {stream?, _, _} = flags(packet)
      stream?
    end

    def body_type(packet) do
      {_, _, body_type} = flags(packet)
      case body_type do
        0 -> :binary
        1 -> :utf8
        2 -> :json
      end
    end

    defp flags(<<flags :: bits-8, _rest :: binary>>) do
      <<0 :: 4, stream? :: 1, end_or_error? :: 1, body_type :: 2>> = flags
      {stream? == 1, end_or_error? == 1, body_type}
    end
  end
end
