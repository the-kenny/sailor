defmodule Sailor.MessageProcessing.Handlers.About do
  require Logger

  alias Sailor.Peer
  alias Sailor.Blob

  def handle!(db, _message_id, message) do
    message_content = Enum.into(message.content, %{})
    identifier = message_content["about"]
    same_as = message_content["sameAs"]

    case identifier do
      <<"@", _rest :: binary>> -> handle_identifier!(db, identifier, message_content)
      <<"%", _rest :: binary>> -> Logger.warn "Unimplemented: About messages for other messages/gatherings #{inspect identifier}"
      [{"feedKey", _dentifier}] -> Logger.warn "Unimplemented: About messages with identifier #{inspect identifier}"
      nil when not is_nil(same_as) -> Logger.warn("Unimplemented: sameAs for message #{message.id}")
      nil -> Logger.warn "Got no identifier for about message #{message.id}"
    end
  end

  def handle_identifier!(db, identifier, message_content) do
    peer = Peer.for_identifier(db, identifier)

    image_blob = case message_content["image"] do
      blob when is_binary(blob) -> blob
      proplist when is_list(proplist) -> :proplists.get_value("link", proplist, nil)
      _ -> nil
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
end
