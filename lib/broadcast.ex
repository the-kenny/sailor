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
    interfaces = Enum.filter(interfaces, fn {ip, _, _} -> ip != {127,0,0,1} end)
    Enum.each interfaces, fn {ip, _, _} ->
      message = "net:" <> to_string(:inet.ntoa(ip)) <> ":" <> Integer.to_string(port) <> "~shs:" <> Base.encode64(keypair.pub)
      Logger.debug "Broadcasting #{message}"
      :gen_udp.send(socket, {255, 255, 255, 255}, port, message)
    end

    {:noreply, state}
  end

  def handle_info({:udp, _socket, _address, _port, data}, state) do
    alias Sailor.Handshake.Keypair
    Logger.debug "Received UDP broadcast: #{data}"
    with [^data, ip, port, public_key] <- Regex.run(~r/^net:(.+):(\d+)~shs:(.+)$/, data),
          {:ok, public_key} <- Base.decode64(public_key),
          {:ok, ip} <- :inet.parse_address(to_charlist ip),
          {port, ""} <- Integer.parse(port),
          keypair = %Keypair{curve: :ed25519, pub: public_key}
    do
      Logger.info("Received broadcast from #{Keypair.id keypair} at #{inspect {ip, port}}")
      {:ok, {keypair, ip, port}}
    else
      err -> Logger.error(inspect err)
    end

    {:noreply, state}
  end
end
