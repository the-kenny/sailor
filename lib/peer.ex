defmodule Sailor.Peer do
  use GenServer

  require Logger

  defmodule State do
    defstruct [
    ]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  # Start as a Client peer
  def run(peer, socket, identity, {:client, server_pubkey}) do
    network_identifier = Sailor.LocalIdentity.network_identifier
    :ok = :gen_tcp.controlling_process(socket, peer)
    :ok = GenServer.cast(peer, {:do_handshake, socket, {identity, server_pubkey, network_identifier}})
    :ok
  end

  # Start as a Server peer
  def run(peer, socket, identity, :server) do
    network_identifier = Sailor.LocalIdentity.network_identifier
    :ok = :gen_tcp.controlling_process(socket, peer)
    :ok = GenServer.cast(peer, {:do_handshake, socket, {identity, network_identifier}})
    :ok
  end

  # Callbacks

  def init([]) do
    {:ok, %State{}}
  end

  def handle_cast({:initialize, socket}, state) do
    {:noreply, %{state | socket: socket}}
  end

  def handle_cast({:do_handshake, socket, handshake_data}, state) do
    alias Sailor.Handshake.Keypair

    {:ok, handshake} = Sailor.Peer.Handshake.run(socket, handshake_data)
    them = %Keypair{pub: handshake.other_pubkey}
    us = handshake.identity
    Logger.info "Successful handshake between #{Keypair.id(us)} (us) and #{Keypair.id(them)} (them)"

    {:ok, reader, writer} = Sailor.Boxstream.IO.open(socket, handshake)

    Task.start_link(fn ->
      alias Sailor.Rpc
      Enum.each 1..999, fn _i ->
        <<packet_header :: binary>> = IO.binread(reader, 9)
        content_length = Rpc.Packet.body_length(packet_header)
        Logger.debug "Got packet header: type=#{Rpc.Packet.body_type(packet_header)} body_length=#{Rpc.Packet.body_length(packet_header)}"
        <<packet_body :: binary>> = IO.binread(reader, content_length)
        packet = packet_header <> packet_body
        IO.inspect {
          Rpc.Packet.request_number(packet),
          Rpc.Packet.body_type(packet),
          Rpc.Packet.body_length(packet),
          packet_body
        }
      end
    end)

    # Task.start_link(fn ->
    #   {:ok, writer} = Sailor.Boxstream.IO.writer(socket, encrypt)
    #   IO.binwrite(writer, <<"HELLO">>)
    # end)

    {:noreply, state}
  end
end
