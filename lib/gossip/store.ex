defmodule Sailor.Gossip.Store do
  alias Sailor.Message

  require Logger

  def store(message) do
    message_sequence = Message.sequence(message)

    {:ok, result} = File.open(stream_path(Message.author(message)), [:read, :write, :append], fn resource ->
      {:ok, last_sequence} = verify(resource)

      cond do
        last_sequence >= message_sequence ->
          Logger.warn "Already stored gossip message with sequence #{message_sequence} from #{Message.author(message)}"
          :ok
        last_sequence+1 == message_sequence -> IO.write(resource, [Message.to_compact_json(message), "\n"])
        :else -> {:error, "Missing messages. Latest stored sequence is #{last_sequence}, asked to store #{message_sequence}"}
      end
    end)

    result
  end

  def for_identifier(identifier) do
    path = stream_path(identifier)
    :ok = File.mkdir_p(Path.dirname(path))

    {:ok, file} = File.open(path, [:read, :write, :append])
    {:ok, last_sequence} = verify(file)

    {:ok, {file, last_sequence}}
  end

  defp verify(resource) do
    result = IO.binstream(resource, :line)
    |> Stream.map(&Sailor.Message.from_json/1)
    |> Stream.map(fn {:ok, message} -> message end)
    |> Enum.reduce_while(0, fn(message, previous_sequence) ->
      if Message.sequence(message) != previous_sequence+1 do
        {:halt, {:error, "Unexpected sequence number #{Message.sequence(message)}"}}
      else
        {:cont, previous_sequence + 1}
      end
    end)

    case result do
      {:error, err} -> {:error, err}
      last_sequence -> {:ok, last_sequence}
    end
  end

  @base_path Path.join(Application.get_env(:sailor, :data_path) , "gossip")

  defp stream_path(identifier) do
    dir = String.slice(identifier, 1..2) |> String.downcase()
    Path.join([@base_path, dir, identifier <> ".json"])
  end
end
