defmodule Sailor.Rpc.HandlerRegistry.CreateHistoryStream do
  require Logger
  alias Sailor.Rpc.Call

  @behaviour Sailor.Rpc.Handler

  @impl Sailor.Rpc.Handler
  def function_names(), do: [
    ["createHistoryStream"],
  ]

  @impl Sailor.Rpc.Handler
  def init([]) do
    {:ok, nil}
  end

  @impl Sailor.Rpc.Handler
  def handle_request(_peer, _rpc_call, state) do
    {:ok, state}
  end
end
