defmodule Sailor.Rpc.Handler.Blobs do
  use GenServer
  require Logger

  def start_link([blobs_path]) do
    GenServer.start_link(__MODULE__, [blobs_path], name: __MODULE__)
  end

  # Callbacks

  def init([blobs_path]) do
    {:ok, blobs_path, {:continue, :register_as_handler}}
  end

  def handle_continue(:register_as_handler, blobs_path) do
    Sailor.Rpc.HandlerRegistry.register_handler(["blobs", "has"], self())
    {:noreply, blobs_path}
  end

  def handle_info({:rpc_request, ["blobs", "has"], "async", [blob_id], peer}, state) do
    Logger.info "Searching for Blob #{blob_id} (for peer #{inspect peer})"
    {:noreply, state}
  end
end
