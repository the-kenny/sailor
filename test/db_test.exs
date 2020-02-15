defmodule Sailor.DbTest do
  use ExUnit.Case

  alias Sailor.Db

  test "initialized?" do
    {:ok, db} = Exqlite.start_link(database: ':memory:')

    assert Db.initialized?(db) == false
    :ok = Db.initialize!(db)
    assert Db.initialized?(db) == true
  end
end
