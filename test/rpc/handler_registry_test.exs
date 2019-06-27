defmodule Sailor.Rpc.HandlerRegistryTest do
  use ExUnit.Case
  doctest Sailor.Rpc.HandlerRegistry

  alias Sailor.Rpc.HandlerRegistry
  alias Sailor.Rpc.Call

  test "register_handler raises for duplicate fns" do
    defmodule Test do
      @behaviour Sailor.Rpc.Handler

      @impl Sailor.Rpc.Handler
      def init([]) do
        {:ok, nil}
      end

      @impl Sailor.Rpc.Handler
      def function_names(), do: [["foo", "bar"]]

      @impl Sailor.Rpc.Handler
      def handle_request(_peer, _call, state) do
        {:ok, state}
      end
    end

    {:ok, _child} = HandlerRegistry.register_handler(Sailor.Rpc.HandlerRegistryTest.Test, [])
    peer = self() # Hack
    assert :ok = HandlerRegistry.dispatch(peer, %Call{name: ["foo", "bar"]})
    assert {:error, _} = HandlerRegistry.dispatch(peer, %Call{name: ["asdf"]})
  end

end
