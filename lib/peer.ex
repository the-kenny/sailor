defmodule Sailor.Peer do
  defstruct [
    identifier: nil,
    name: nil,
    image_blob: nil,
    contacts: MapSet.new(),
  ]

  def for_identifier(db, identifier) do
    {:ok, result} = Exqlite.query(db, "select peers.*, group_concat(peer_contacts.contact) as following from peers left join peer_contacts on peers.identifier = peer_contacts.peer where peers.identifier = ?", [identifier])
    [row] = result.rows
    case from_row(identifier, row) do
      nil -> persist!(db, %__MODULE__{identifier: identifier})
      peer -> peer
    end
  end

  defp from_row(identifier, row) do
    if Keyword.get(row, :identifier) do
      peers = case Keyword.get(row, :following, nil) do
        nil -> MapSet.new()
        "" -> MapSet.new()
        s -> s |> String.split(",") |> Enum.into(MapSet.new())
      end

      %__MODULE__{
        identifier: identifier,
        name: Keyword.get(row, :name, nil),
        image_blob: Keyword.get(row, :image_blob, nil),
        contacts: peers
      }
    else
      nil
    end
  end

  def persist!(db, peer) do
    {:ok, _} = Exqlite.query(db, "insert or replace into peers (identifier, name, image_blob) values (?, ?, ?)", [
      peer.identifier,
      peer.name,
      peer.image_blob,
    ])

    with {:ok, result} <- Exqlite.query(db, "select contact from peer_contacts where peer = ? and status = 1", [peer.identifier]),
         rows = result.rows,
         old_contacts = rows |> Enum.map(&Keyword.get(&1, :contact)) |> Enum.into(MapSet.new)
    do
      for removed_contact <- MapSet.difference(old_contacts, peer.contacts) do
        {:ok, _} = Exqlite.query(db, "delete from peer_contacts where peer = ? and contact = ?", [peer.identifier, removed_contact])
      end

      for added_contact <- MapSet.difference(peer.contacts, old_contacts) do
        {:ok, _} = Exqlite.query(db, "insert into peer_contacts (peer, contact) values (?, ?)", [peer.identifier, added_contact])
      end
    end

    peer
  end

  # def all_following(db,) do
  #   {:ok, rows} = Sqlitex.query(db, "select * from peers where following is true")
  #   Enum.map(rows, &from_row/1)
  # end

  # def all_following(peer), do: Sailor.Db.with_db(&all_following(&1, peer))
end
