defmodule Sailor.Rpc.HandlerRegistry.Blobs do
  require Logger
  alias Sailor.Rpc.Packet
  alias Sailor.Rpc.Call
  alias Sailor.Peer

  @behaviour Sailor.Rpc.Handler

  @impl Sailor.Rpc.Handler
  def function_names(), do: [
    ["blobs", "has"],
    ["blobs", "createWants"],
  ]

  @impl Sailor.Rpc.Handler
  def init([blobs_path]) do
    {:ok, blobs_path}
  end

  @impl Sailor.Rpc.Handler
  def handle_request(peer, %Call{name: ["blobs", "createWants"]} = rpc_call, blobs_path) do
    :ok = create_wants(peer, rpc_call.packet)
    {:ok, blobs_path}
  end


  # @impl GenServer
  # def handle_info({:rpc_request, ["blobs", "has"], "async", [blob_id], request_packet, peer_identifier}, state) do
  #   Logger.info "Searching for Blob #{blob_id} (for request #{Packet.request_number(request_packet)} of peer #{peer_identifier}"

  #   packet = Packet.respond(request_packet)
  #   |> Packet.body_type(:json)
  #   |> Packet.body(Jason.encode!(false))

  #   Sailor.Peer.for_identifier(peer_identifier)
  #   |> Sailor.Peer.send_rpc_response(packet)

  #   {:noreply, state}
  # end

  def create_wants(peer, packet) do
    Sailor.Blob.all_wanted()
    |> Enum.map(fn {blob, severity} -> Packet.respond(packet) |> Packet.body_type(:json) |> Packet.body(Jason.encode!(%{blob => severity})) end)
    |> Enum.each(&Sailor.Peer.send_rpc_response(peer, &1))

    :ok
  end
end
