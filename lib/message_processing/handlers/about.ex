defmodule Sailor.MessageProcessing.Handlers.About do
  require Logger

  alias Sailor.Keypair
  alias Sailor.Peer
  alias Sailor.Blob

  def handle!(db, _message_id, message_content) do
    identifier = message_content["about"]
    if identifier && String.starts_with?(identifier, "@") do
      peer = Peer.for_identifier(identifier)

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
