defmodule Sailor.MessageProcessing.Handlers.Contact do
  require Logger

  alias Sailor.Peer

  def handle!(db, _message_id, message) do
    content = Enum.into(message.content, %{})

    if Map.has_key?(content, "following") do
      # Message %4Mc96z8FMZJRTSiGMaXkzsB1CJnfBt3dpTWD6GC7+lw=.sha256 has `contacts` instead of `contact`
      contact = content["contact"] || content["contacts"]
      following? = content["following"] || false

      if contact do
        case Sailor.Keypair.from_identifier(contact) do
          {:error, _err} -> Logger.warn "Failed to handle message #{message.id}: Invalid contact identifier #{inspect contact}"
          {:ok, keypair} -> update_follow!(db, message.author, Sailor.Keypair.identifier(keypair), following?)
        end
      end
    end
  end

  defp update_follow!(db, peer, contact_identifier, following?) do
    for identifier <- [peer, contact_identifier] do
      Peer.for_identifier(db, identifier)
    end

    {:ok, _} = if following? do
      Exqlite.query(db, "insert or ignore into peer_contacts (peer, contact) values(?, ?)", [peer, contact_identifier])
    else
      Exqlite.query(db, "delete from peer_contacts where peer = ? and contact = ?", [peer, contact_identifier])
    end

  end
end
