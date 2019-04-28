defmodule Sailor.Peer do
  use GenServer

  require Logger

  # Start as a Client peer
  def start_link(socket, server_pubkey) do
    identity = Sailor.Identity.keypair
    network_identifier = Sailor.Identity.network_identifier
    GenServer.start_link(__MODULE__, [socket, {identity, server_pubkey, network_identifier}])
  end

  # Start as a Server peer
  def start_link(socket) do
    identity = Sailor.Identity.keypair
    network_identifier = Sailor.Identity.network_identifier
    GenServer.start_link(__MODULE__, [socket, {identity, network_identifier}])
  end


  def init([socket, handshake_data]) do
    {:ok, socket, {:continue, {:do_handshake, handshake_data}}}
  end

  # def handle_info({:tcp, socket, msg}, state) do
  #   Logger.info "Got data: #{inspect msg}"

  #   {:noreply, state}
  # end

  # def handle_info({:tcp_closed, socket}, state) do
  #   {:stop, :normal, nil}
  # end

  def handle_continue({:do_handshake, handshake_data}, socket) do
    alias Sailor.Handshake.Keypair

    {:ok, handshake} = Sailor.Peer.Handshake.run(socket, handshake_data)
    them = %Keypair{pub: handshake.other_pubkey}
    us = handshake.identity
    Logger.info "Successful handshake between #{Keypair.id(us)} (us) and #{Keypair.id(them)} (them)"

    {:noreply, socket}
  end
end
