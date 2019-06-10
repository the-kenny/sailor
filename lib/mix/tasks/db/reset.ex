defmodule Mix.Tasks.Db.Reset do
  use Mix.Task

  @modules [
    Sailor.Message
  ]

  @shortdoc "Resets the local Mnesia database and initializes the schema"
  def run(_) do
    Memento.stop
    nodes = [node()]
    Memento.Schema.delete(nodes)
    Memento.Schema.create(nodes)
    Memento.start

    Enum.each(@modules, &Memento.Table.create!(&1, disc_copies: nodes))

  end
end