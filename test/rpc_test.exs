defmodule Sailor.RpcTest do
  use ExUnit.Case
  doctest Sailor.Rpc
end

defmodule Sailor.Rpc.PacketTest do
  use ExUnit.Case
  doctest Sailor.Rpc.Packet

  alias Sailor.Rpc.Packet

  @packet Packet.stream(42, :utf8, "HELLO")

  test "request_number" do
    assert Packet.request_number(@packet) == 42
    assert Packet.request_number(Packet.stream(-42, :utf8, "HELLO")) == -42
  end
  test "body_type", do: assert Packet.body_type(@packet) == :utf8
  test "stream?", do: assert Packet.stream?(@packet) == true
  test "body_length", do: assert Packet.body_length(@packet) == 5
  test "end_or_error?", do: assert Packet.end_or_error?(@packet) == false
end
