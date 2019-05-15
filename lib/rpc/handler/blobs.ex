defmodule Sailor.Rpc.Handler.Blobs do
  use GenServer
  require Logger

  alias Sailor.Rpc.Packet

  @supported_rpcs [
    ["blobs", "has"],
    ["blobs", "createWants"],
  ]

  def start_link([blobs_path]) do
    GenServer.start_link(__MODULE__, [blobs_path], name: __MODULE__)
  end

  # Callbacks

  def init([blobs_path]) do
    {:ok, blobs_path, {:continue, :register_as_handler}}
  end

  def handle_continue(:register_as_handler, blobs_path) do
    Enum.each(@supported_rpcs, &Sailor.Rpc.HandlerRegistry.register_handler(&1, self()))
    {:noreply, blobs_path}
  end

  def handle_info({:rpc_request, ["blobs", "has"], "async", [blob_id], request_packet, rpc}, state) do
    Logger.info "Searching for Blob #{blob_id} (for request #{Packet.request_number(request_packet)}"

    packet = Packet.respond(request_packet)
    |> Packet.body_type(:json)
    |> Packet.body(Jason.encode!(false))

    Sailor.Rpc.send_packet(rpc, packet)

    {:noreply, state}
  end

  def handle_info({:rpc_request, ["blobs", "createWants"], "source", [], request_packet, rpc}, state) do
    responses = [
      # %{"&jqp3ImUpZZ4QD/AcST54J24aGaB3lJg5IDG82TeBmN4=.sha256": -1},
      # %{"&/zFse6nZCK5eOuaAz/NrPj929olH2TMZ5ovGZBZzoQU=.sha256": -1},
    ]

    responses
    |> Enum.map(fn response -> Packet.respond(request_packet) |> Packet.body_type(:json) |> Packet.body(Jason.encode!(response)) end)
    |> Enum.each(&Sailor.Rpc.send_packet(rpc, &1))

    {:noreply, state}
  end
end
