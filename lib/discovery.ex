defmodule Sailor.Discovery do
  alias Sailor.Handshake.Keypair

  use GenServer

  def start_link([]) do
    port = 8008
    keypair = Keypair.random

    GenServer.start_link(__MODULE__, {port, keypair}) # Start 'er up
  end

  def init({port, keypair}) do
    :timer.send_interval 1*1000, :broadcast
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true, broadcast: true])
    {:ok, {socket, port, keypair}}
  end

  def handle_info(:broadcast, state) do
    {socket, port, keypair} = state

    Enum.each(broadcast_msgs(port, keypair), fn data ->
      :gen_udp.send socket, {255, 255, 255, 255}, port, data
    end)

    {:noreply, state}
  end

  def handle_info({:udp, _socket, _address, _port, data}, state) do
    # punt the data to a new function that will do pattern matching
    # IO.inspect data
    {:noreply, state}
  end

  def broadcast_msgs(port, %Keypair{} = keypair) do
    base64_pubkey = Base.encode64(keypair.pub)

    Enum.map(broadcast_ips(), fn ip ->
      "net:" <> to_string(:inet.ntoa(ip)) <> ":" <> Integer.to_string(port) <> "~shs:" <> base64_pubkey
    end)
  end

  def broadcast_ips() do
    {:ok, iflist} = :inet.getifaddrs
    iflist
    |> Enum.map(fn {_ifname, opts} -> Keyword.get(opts, :addr) end)
    |> Enum.filter(&is_tuple/1)
  end
end
