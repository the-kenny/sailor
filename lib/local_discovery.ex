alias Sailor.Keypair

defmodule Sailor.LocalDiscover do
  use GenServer

  require Logger

  def start_link([port, identity]) do
    GenServer.start_link(__MODULE__, {port, identity})
  end

  def init({port, identity}) do
    enabled? = Application.get_env(:sailor, __MODULE__) |> Keyword.get(:enabled?, false)

    if !enabled? do
      :ignore
    else
      :timer.send_interval 5*1000, :broadcast

      with {:ok, socket} <- :gen_udp.open(port, [:binary, active: true, broadcast: true])
      do
        {:ok, {socket, identity, %{}}}
      else
        {:error, :eaddrinuse} ->
          Logger.warn "Couldn't start broadcast: Address in use"
          :ignore
      end
    end
  end

  def handle_info(:broadcast, {socket, identity, _known_peers} = state) do
    {:ok, {_ip, port}} = :inet.sockname(socket)
    {:ok, interfaces} = :inet.getif()
    interfaces = Enum.filter(interfaces, fn {ip, _, _} -> ip != {127,0,0,1} end)
    Enum.each interfaces, fn {ip, _, _} ->
      message = "net:" <> to_string(:inet.ntoa(ip)) <> ":" <> Integer.to_string(port) <> "~shs:" <> Base.encode64(identity.pub)
      # Logger.debug "Broadcasting #{message}"
      :ok = :gen_udp.send(socket, {255, 255, 255, 255}, port, message)
    end

    {:noreply, state}
  end

  def handle_info({:udp, _socket, _address, _port, data}, {socket, identity, known_peers} = state) do
    with [^data, ip, port, public_key] <- Regex.run(~r/^net:(.+):(\d+)~shs:(.+)$/, data),
          {:ok, public_key} <- Base.decode64(public_key),
          {:ok, ip} <- :inet.parse_address(to_charlist ip),
          {port, ""} <- Integer.parse(port),
          keypair = Keypair.from_pubkey(public_key)
    do
      known_peers = if !Map.has_key?(known_peers, keypair) do
        Logger.debug ("Received broadcast from #{Keypair.id keypair} at #{inspect {:inet.ntoa(ip), port}}")
        Map.put(known_peers, keypair, {ip, port})
      else
        known_peers
      end
      {:noreply, {socket, identity,known_peers}}

    else
      _ ->
        Logger.error("Failed to parse UDP broadcast: #{inspect data}")
        {:noreply, state}
    end


  end
end
