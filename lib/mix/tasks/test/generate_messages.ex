defmodule Mix.Tasks.Test.GenerateMessages do
  use Mix.Task

  def run(_) do
    File.open!("priv/tests/messages", [:write, :utf8, :create], fn f ->
      System.cmd("sbot", ["createLogStream", "--limit=10000", "--no-values"])
      |> elem(0)
      |> String.split("\n\n")
      |> Enum.shuffle()
      |> Enum.take(200)
      |> Enum.each(fn key ->
        key = key |> String.trim() |> String.trim("\"")
        src = System.cmd("sbot", ["get", key]) |> elem(0)
        IO.write(f, [key, "\n", src, "\n"])
      end)
    end)
  end
end
