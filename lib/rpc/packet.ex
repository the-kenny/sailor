defmodule Sailor.Rpc.Packet do
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

  def end_or_error(packet) do
    packet_binary() = packet
    end_or_error? = 1
    packet_binary()
  end

  @goodbye_packet <<0, 0, 0, 0, 0, 0, 0, 0, 0>>

  def goodbye_packet?(packet) when packet == @goodbye_packet, do: true
  def goodbye_packet?(_packet), do: false

  def goodbye_packet() do
    @goodbye_packet
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

  def respond(packet) do
    packet
    |> request_number(-request_number(packet))
    |> body(<<>>)
  end

  # Utility Functions

  @spec rpc_call?(binary()) :: boolean
  def rpc_call?(packet) do
    rpc_call(packet) != nil
  end

  @spec rpc_call(binary()) :: %Sailor.Rpc.Call{} | nil
  def rpc_call(packet) do
    case {body_type(packet), Jason.decode(body(packet))} do
      {:json, {:ok, %{"name" => name, "type" => type, "args" => args}}} ->
        %Sailor.Rpc.Call{
          name: name,
          args: args,
          type: type,
          packet: packet,
        }
      _ -> nil
    end
  end

  # Packet Info Struct

  defmodule Info do
    defstruct [
      request_number: nil,
      stream?: nil,
      end_or_error?: nil,
      body_type: nil,
      body_length: nil,
      body: nil,
    ]
  end

  @doc """
  ## Examples

      iex> packet = create() |> stream() |> request_number(42) |> body_type(:utf8) |> body("HELLO")
      iex> info(packet)
      %Sailor.Rpc.Packet.Info{
        request_number: 42,
        stream?: true,
        end_or_error?: false,
        body_type: :utf8,
        body_length: 5,
        body: "HELLO"
      }

  """
  @spec info(binary()) :: %Sailor.Rpc.Packet.Info{}
  def info(packet) do
    packet_binary() = packet

    body_type = case body_type do
      0 -> :binary
      1 -> :utf8
      2 -> :json
    end

    %Sailor.Rpc.Packet.Info{
      request_number: request_number,
      stream?: stream? == 1,
      end_or_error?: end_or_error? == 1,
      body_type: body_type,
      body_length: body_length,
      body: body,
    }
  end
end
