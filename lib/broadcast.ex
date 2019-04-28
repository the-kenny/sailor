defmodule Sailor.Broadcast do
  use GenServer

  require Logger

  def start_link([port, identity]) do
    GenServer.start_link(__MODULE__, {port, identity})
  end

  def init({port, keypair}) do
    :timer.send_interval 5*1000, :broadcast

    {:ok, socket} = :gen_udp.open(port, [:binary, active: true, broadcast: true])
    {:ok, {socket, keypair}}
  end

  def handle_info(:broadcast, {socket, keypair} = state) do
    {:ok, {_ip, port}} = :inet.sockname(socket)
    {:ok, interfaces} = :inet.getif()
    Enum.each interfaces, fn {ip, _, _} ->
      message = "net:" <> to_string(:inet.ntoa(ip)) <> ":" <> Integer.to_string(port) <> "~shs:" <> Base.encode64(keypair.pub)
      Logger.debug "Broadcasting #{message}"
      :gen_udp.send(socket, {255, 255, 255, 255}, port, message)
    end

    {:noreply, state}
  end

  def handle_info({:udp, _socket, _address, _port, data}, state) do
    # punt the data to a new function that will do pattern matching
    # IO.inspect data
    {:noreply, state}
  end
end
