defmodule Sailor.Peer do
  alias Sailor.Db

  defstruct [
    identifier: nil,
    name: nil,
    image_blob: nil,
    following?: false,
  ]

  def for_identifier(identifier) do
    case Db.with_db(&Sqlitex.query(&1, "select * from peers where identifier = ?", bind: [identifier])) do
      {:ok, [row]} -> from_row(row)
      {:ok, []} -> %__MODULE__{identifier: identifier}
    end
  end

  defp from_row(row) do
    %__MODULE__{
      identifier: Keyword.get(row, :identifier),
      name: Keyword.get(row, :name, nil),
      image_blob: Keyword.get(row, :image_blob, nil),
      following?: Keyword.get(row, :following, false),
    }
  end

  def persist(peer), do: Db.with_db(&persist!(&1, peer))

  def persist!(db, peer) do
    {:ok, _} = Sqlitex.query(db, "insert or replace into peers (identifier, name, image_blob, following) values (?, ?, ?, ?)", bind: [
      peer.identifier,
      peer.name,
      peer.image_blob,
      peer.following?,
    ])
  end
end
