defmodule Sailor.Stream do
  alias Sailor.Stream.Message

  require Logger

  defstruct [
    identifier: nil,
    sequence: 0,
    messages: []
  ]

  def from_messages(identifier, messages) do
    Enum.each(messages, fn message ->
      if Message.author(message) != identifier do
        raise "Message #{Message.id(message)} doesn't match author #{identifier}"
      end
    end)

    sequence = messages
    |> Stream.map(&Message.sequence/1)
    |> Enum.max(fn -> 0 end)

    %__MODULE__{
      identifier: identifier,
      sequence: sequence,
      messages: Enum.sort_by(messages, &Message.sequence/1)
    }
  end

  def persist!(stream) do
    Sailor.Db.with_db(fn(db) ->
      # TODO: Use `with_transaction`
      :ok = Sqlitex.exec(db, "begin")

      {:ok, [[sequence: seq]]} = Sqlitex.query(db, "select max(sequence) as sequence from stream_messages where author = ?", bind: [stream.identifier])
      seq = seq || 0

      for message <- Enum.filter(stream.messages, &Message.sequence(&1) > seq) do
        Sqlitex.query!(db, "insert or ignore into stream_messages (id, author, sequence, json) values (?1, ?2, ?3, ?4)", bind: [
          Message.id(message),
          Message.author(message),
          Message.sequence(message),
          Message.to_compact_json(message)
        ])
      end
      :ok = Sqlitex.exec(db, "commit");
      :ok
    end)
  end

  def for_peer(identifier) do
    message_stream = Sailor.Db.with_db(fn db ->
      with {:ok, result} <- Sqlitex.query(db, "select json from stream_messages where author = ? order by sequence", bind: [identifier])
      do
        result
        |> Stream.map(&Keyword.get(&1, :json))
        |> Stream.map(fn json ->
          {:ok, message} = Message.from_json(json)
          message
        end)
      end
    end)

    from_messages(identifier, Enum.into(message_stream, []))
  end

  def append(stream, []), do: {:ok, stream}

  def append(stream, [message]) do
    seq = Message.sequence(message)
    author = Message.author(message)

    cond do
      seq > (stream.sequence + 1) ->
        {:error, "Invalid sequence number: Missing at least one message between #{stream.sequence} and #{seq}"}
      seq <= stream.sequence ->
        {:ok, stream}
      author != stream.identifier ->
        {:error, "Wrong wuthor #{author}"}
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

  @doc """

  """
  def extract_peers(stream) do
    stream.messages
    |> Stream.map(&Message.content/1)
    |> Stream.reject(&is_binary/1)
    |> Stream.map(&:proplists.get_value("text", &1, nil))
    |> Stream.filter(&is_binary/1)
    |> Stream.flat_map(&Sailor.Utils.extract_identifiers/1)
    |> Enum.into(MapSet.new())
  end

  # defp validate(stream) do
  #   stream = stream.messages |> Enum.sort_by(&Message.sequence/1)
  #   seq_check_result = Enum.map(stream.messages, &Message.sequence/1)
  #   |> Enum.reduce(1, fn expected, got ->
  #     if expected == got do
  #       got + 1
  #     else
  #       {:halt, expected, got}
  #     end
  #   end)

  #   case seq_check_result do
  #     n when is_number(n) -> stream
  #     {:error, expected, got} ->
  #       raise "Invalid Sequence. Expected #{expected} got #{got}"
  #   end
  # end
end
