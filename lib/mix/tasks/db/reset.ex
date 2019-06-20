defmodule Mix.Tasks.Db.Reset do
  use Mix.Task

  alias Sqlitex

  @shortdoc "Resets the local sqlite database and initializes the schema"
  def run(_) do
    db_path = Path.join([Application.get_env(:sailor, :data_path), "data.sqlite"])
    File.mkdir_p!(Path.dirname(db_path))
    File.touch!(db_path)

    schema_file = Path.join([Application.app_dir(:sailor), "priv", "schema.sql"])

    :ok = Sqlitex.with_db(db_path, fn(db) ->
      :ok = Sqlitex.exec(db, File.read!(schema_file))
      :ok = Sqlitex.exec(db, "vacuum")
    end)
  end
end
