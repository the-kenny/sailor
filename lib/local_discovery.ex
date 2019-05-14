alias Sailor.Keypair

# TODO: Split into Broadcast and Announce
defmodule Sailor.LocalDiscovery do
  use GenServer

  require Logger

  def start_link([port, identity]) do
    GenServer.start_link(__MODULE__, {port, identity}, name: __MODULE__)
  end

  def init({port, identity}) do
    config = Application.get_env(:sailor, __MODULE__)

    if !Keyword.get(config, :enable) do
      Logger.info "Disabling local discovery and broadcast"
      :ignore
    else
      Logger.info "Starting local discovery and broadcast"

      case Keyword.get(config, :broadcast_interval) do
        nil -> Logger.info "No `:broadcast_interval` configured."
        n ->
          Logger.info "Broadcasting every #{inspect n}ms"
          :timer.send_interval(n, :broadcast)
      end

      with {:ok, socket} <- :gen_udp.open(port, [:binary, active: true, broadcast: true])
      do
        {:ok, {socket, identity}}
      else
        err ->
          Logger.warn "Couldn't start local discovery and broadcast: #{inspect err}"
          err
      end
    end
  end

  @peer_connection_re ~r/^net:(.+):(\d+)~shs:(.+)$/

  def parse_announcement(data) do
    with [^data, ip, port, public_key] <- Regex.run(@peer_connection_re, data),
         {:ok, public_key} <- Base.decode64(public_key),
         {:ok, ip} <- :inet.parse_address(to_charlist ip),
         {port, ""} <- Integer.parse(port),
         keypair = Keypair.from_pubkey(public_key)
    do
      {:ok, ip, port, keypair}
    else
      _ -> {:error, data}
    end
  end

  def parse_announcements(data) do
    String.split(data, ";")
    |> Stream.map(&parse_announcement/1)
    |> Stream.filter(&Kernel.match?({:ok, _ip, _port, _public_key}, &1))
  end

  def handle_info(:broadcast, {socket, identity} = state) do
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

  def handle_info({:udp, _socket, _address, _port, data}, state) do
    Enum.each(parse_announcements(data), fn {:ok, ip, port, keypair} ->
      identifier = Keypair.id(keypair)
      if Sailor.Gossip.get_peer(identifier) == nil do
        Logger.debug "Received broadcast from #{identifier} at #{inspect {:inet.ntoa(ip), port}}"
      end

      Sailor.Gossip.remember_peer(identifier, {ip, port})
    end)

    {:noreply, state}
  end
end
