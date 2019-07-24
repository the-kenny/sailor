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
        update_follow!(db, message.author, contact, following?)
      end
    end
  end

  defp update_follow!(db, peer, contact, following?) do
    {:ok, keypair} = Sailor.Keypair.from_identifier(contact)
    identifier = Sailor.Keypair.identifier(keypair)

    for identifier <- [peer, identifier] do
      Peer.for_identifier(identifier)
    end

    {:ok, _} = if following? do
      Sqlitex.query(db, "insert or ignore into peer_contacts (peer, contact) values(?, ?)", bind: [ peer, identifier ])
    else
      Sqlitex.query(db, "delete from peer_contacts where peer = ? and contact = ?", bind: [ peer, identifier ])
    end

  end
end
