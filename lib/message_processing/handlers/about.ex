defmodule Sailor.MessageProcessing.Handlers.About do
  require Logger

  alias Sailor.Peer
  alias Sailor.Blob
  alias Sailor.Stream.Message

  def handle!(db, _message_id, message) do
    message_content = Message.content(message) |> Enum.into(%{})
    identifier = message_content["about"]
    if identifier && String.starts_with?(identifier, "@") do
      peer = case Peer.for_identifier(identifier) do
        nil -> Peer.persist!(%Peer{identifier: identifier})
        peer -> peer
      end

      image_blob = case message_content["image"] do
        blob when is_binary(blob) -> blob
        proplist when is_list(proplist) -> :proplists.get_value("link", proplist, nil)
        nil -> nil
      end

      if image_blob && Blob.valid?(image_blob) do
        Blob.mark_wanted!(db, image_blob, -1)
      end

      peer = %{peer |
        name: message_content["name"] || peer.name,
        image_blob: image_blob || peer.image_blob,
      }

      Peer.persist!(db, peer)
    end

    # TODO: Handle `sameAs`
  end
end
