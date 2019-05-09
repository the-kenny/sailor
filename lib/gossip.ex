defmodule Sailor.Gossip do
  use Agent

  def start_link([]) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def all_peers(gossip \\ __MODULE__) do
    Agent.get(gossip, fn peers -> peers end)
  end

  def get_peer(gossip \\ __MODULE__, identifier) do
    Agent.get(gossip, fn peers -> Map.get(peers, identifier) end)
  end

  def remember_peer(gossip \\ __MODULE__, identifier, {ip, port}) do
    Agent.update(gossip, fn peers -> Map.put(peers, identifier, {ip, port}) end)
  end
end
