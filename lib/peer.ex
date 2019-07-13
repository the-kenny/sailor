defmodule Sailor.Peer do
  alias Sailor.Db

  defstruct [
    identifier: nil,
    name: nil,
    image_blob: nil,
    followed_peers: MapSet.new(),
  ]

  def for_identifier(identifier) do
    {:ok, [row]} = Db.with_db(&Sqlitex.query(&1, "select peers.*, group_concat(peer_edges.followed_peer) as following from peers left join peer_edges on peers.identifier = peer_edges.peer where identifier = ?", bind: [identifier]))
    from_row(row)
  end

  defp from_row(row) do
    identifier = Keyword.get(row, :identifier)

    if identifier do
      peers = case Keyword.get(row, :following, nil) do
        nil -> MapSet.new()
        "" -> MapSet.new()
        s -> s |> String.split(",") |> Enum.into(MapSet.new())
      end

      %__MODULE__{
        identifier: identifier,
        name: Keyword.get(row, :name, nil),
        image_blob: Keyword.get(row, :image_blob, nil),
        followed_peers: peers
      }
    else
      nil
    end
  end

  def persist!(peer), do: Db.with_db(&persist!(&1, peer))

  def persist!(db, peer) do
    {:ok, _} = Sqlitex.query(db, "insert or replace into peers (identifier, name, image_blob) values (?, ?, ?)", bind: [
      peer.identifier,
      peer.name,
      peer.image_blob,
    ])

    # TODO: Delete/insert only when necessary

    {:ok, _} = Sqlitex.query(db, "delete from peer_edges where peer = ?", bind: [peer.identifier])
    for identifier <- peer.followed_peers do
      {:ok, _} = Sqlitex.query(db, "insert into peer_edges (peer, followed_peer, status) values (?, ?, 1)", bind: [
        peer.identifier,
        identifier
      ])
    end

    peer
  end

  # def all_following(db,) do
  #   {:ok, rows} = Sqlitex.query(db, "select * from peers where following is true")
  #   Enum.map(rows, &from_row/1)
  # end

  # def all_following(peer), do: Sailor.Db.with_db(&all_following(&1, peer))
end
