defmodule Sailor.DbTest do
  use ExUnit.Case

  alias Sailor.Db

  test "initialized?" do
    {:ok, db} = Sqlitex.open(':memory:')

    assert Db.initialized?(db) == false
    :ok = Db.initialize!(db)
    assert Db.initialized?(db) == true
  end
end
