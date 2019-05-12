defmodule Sailor.Peer.Registry do

  def child_spec([]) do
    %{
      id: __MODULE__,
      start: {Registry, :start_link, [[keys: :unique, name: __MODULE__]]}
    }
  end
end
