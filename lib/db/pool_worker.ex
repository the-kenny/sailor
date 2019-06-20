defmodule Sailor.Db.PoolWorker do
  use GenServer

  require Logger

  def start_link([db_path]) do
    GenServer.start_link(__MODULE__, [db_path])
  end

  def init([db_path]) do
    {:ok, db} = Sqlitex.open(db_path)
    :ok = Sqlitex.exec(db, "PRAGMA foreign_keys = ON;")
    {:ok, db}
  end

  def handle_call({:exec, fun}, _from, db) do
    result = apply(fun, [db])
    {:reply, result, db}
  end
end
