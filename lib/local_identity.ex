defmodule Sailor.LocalIdentity do
  use Agent

  def start_link([identity, network_identifier]) do
    Agent.start_link(fn -> {identity, network_identifier} end, name: __MODULE__)
  end

  def keypair do
    Agent.get(__MODULE__, fn {identity, _} -> identity end)
  end

  def network_identifier do
    Agent.get(__MODULE__, fn {_, network_identifier} -> network_identifier end)
  end
end
