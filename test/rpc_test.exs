defmodule Sailor.RpcTest do
  use ExUnit.Case
  doctest Sailor.Rpc
end

defmodule Sailor.Rpc.PacketTest do
  use ExUnit.Case
  doctest Sailor.Rpc.Packet, import: true

  alias Sailor.Rpc.Packet

  @packet Packet.create() |> Packet.stream() |> Packet.request_number(42) |> Packet.body_type(:utf8) |> Packet.body("HELLO")

  test "request_number" do
    assert Packet.request_number(@packet) == 42
    assert Packet.request_number(Packet.request_number(@packet, -42)) == -42
  end

  test "body_type", do: assert Packet.body_type(@packet) == :utf8
  test "stream?", do: assert Packet.stream?(@packet) == true
  test "body_length", do: assert Packet.body_length(@packet) == 5
  test "end_or_error?", do: assert Packet.end_or_error?(@packet) == false

  test "packet_binary macro roundtrip" do
    Packet.packet_binary() = @packet
    assert @packet == Packet.packet_binary()
  end

  test "create()" do
    packet = Packet.create()
    assert Packet.body_length(packet) == 0
    assert Packet.request_number(packet) == 0
  end
end
