defmodule Mix.Tasks.Db.Reset do
  use Mix.Task

  @shortdoc "Resets the local sqlite database and initializes the schema"
  def run(_) do
    db_path = Path.join([Application.get_env(:sailor, :data_path), "data.sqlite"])
    File.mkdir_p!(Path.dirname(db_path))
    File.touch!(db_path)

    schema_file = Path.join([Application.app_dir(:sailor), "priv", "schema.sql"])

    {:ok, db} = Exqlite.start_link(database: db_path)
    :ok = Exqlite.execute_raw(db, File.read!(schema_file))
    :ok = Exqlite.execute_raw(db, "vacuum")
  end
end
