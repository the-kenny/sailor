defmodule Sailor.Db do
  require Logger
  require Exqlite

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  # TODO: Add a `Registry` to make announcement about table updates

  def start_link([db_path]) do
    {:ok, db} = Exqlite.start_link(database: db_path, name: __MODULE__)
    Exqlite.prepare_execute(db, "PRAGMA journal_mode=WAL")

    if !initialized?(db) do
      Logger.info "Initializing database #{inspect db_path}"
      :ok = initialize!(db)
    end

    {:ok, db}
  end

  def initialized?(db) do
    case Exqlite.query(db, "select true from sqlite_master where type = 'table' and name = ?", ["stream_messages"]) do
      {:ok, %Exqlite.Result{rows: []}} -> false
      {:ok, _} -> true
    end
  end

  def initialize!(db) do
    schema_file = Path.join([Application.app_dir(:sailor), "priv", "schema.sql"])

    :ok = Exqlite.execute_raw(db, File.read!(schema_file))
    {:ok, _} = Exqlite.query(db, "vacuum")
    :ok
  end
end
