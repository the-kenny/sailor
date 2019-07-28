defmodule Sailor.Stream do
  alias Sailor.Stream.Message

  require Logger

  defstruct [
    identifier: nil,
    sequence: 0,
    messages: []
  ]

  @spec persist!(%Sailor.Stream{}) :: :ok
  def persist!(stream) do
    Logger.debug "Persisting stream for #{stream.identifier} with sequence #{stream.sequence}"

    rows = Enum.map(stream.messages, fn message ->
      [
        message.id,
        message.author,
        message.sequence,
        Message.to_compact_json(message)
      ]
    end)

    Sailor.Db.with_db(fn(db) ->
      Sailor.Db.with_transaction(db, fn db ->
        {:ok, stmt} = Sqlitex.Statement.prepare(db, "insert or ignore into stream_messages (id, author, sequence, json) values (?1, ?2, ?3, ?4)")

        {:ok, [[sequence: seq]]} = Sqlitex.query(db, "select max(sequence) as sequence from stream_messages where author = ?", bind: [stream.identifier])
        seq = seq || 0

        rows
        |> Enum.filter(fn [_, _, mseq, _] -> mseq > seq end)
        |> Enum.each(fn row ->
          {:ok, stmt} = Sqlitex.Statement.bind_values(stmt, row)
          :ok = Sqlitex.Statement.exec(stmt)
        end)

        :ok
      end)
    end)
  end

  def for_peer(identifier) do
    message_stream = with {:ok, result} <- Sailor.Db.with_db(&Sqlitex.query(&1, "select json from stream_messages where author = ? order by sequence", bind: [identifier]))
    do
      result
      |> Stream.map(&Keyword.get(&1, :json))
      |> Stream.map(fn json ->
        case Message.from_json(json) do
          {:ok, message} -> message
          {:error, error} ->
            raise "#{error}: #{json}"
        end
      end)
    end

    # TODO: Validate that `row.id` matches `Message.id(message)`

    from_messages(identifier, Enum.into(message_stream, []))
  end

  @spec append(%Sailor.Stream{}, [%Sailor.Stream.Message{}]) :: {:ok, %Sailor.Stream{}} | {:error, String.t}
  def append(stream, []), do: {:ok, stream}

  def append(stream, [message]) do
    seq = message.sequence
    author = message.author

    cond do
      seq > (stream.sequence + 1) ->
        {:error, "Invalid sequence number: Missing at least one message between #{stream.sequence} and #{seq}"}
      seq <= stream.sequence ->
        {:ok, stream}
      author != stream.identifier ->
        {:error, "Wrong author #{author}"}
      :else ->
        {:ok, %{ stream |
          sequence: seq,
          messages: stream.messages ++ [message]
        }}
    end
  end

  def append(stream, messages) do
    Enum.reduce_while(messages, {:ok, stream}, fn (message, {:ok, stream}) ->
      case append(stream, [message]) do
        {:ok, stream} -> {:cont, {:ok, stream}}
        err -> {:halt, err}
      end
    end)
  end

  defp from_messages(identifier, messages) do
    Enum.each(messages, fn message ->
      if message.author != identifier do
        raise "Message #{message.id} doesn't match author #{identifier}"
      end
    end)

    sequence = messages
    |> Stream.map(&Map.get(&1, :sequence))
    |> Enum.max(fn -> 0 end)

    %__MODULE__{
      identifier: identifier,
      sequence: sequence,
      messages: Enum.sort_by(messages, &Map.get(&1, :sequence))
    }
  end
end
