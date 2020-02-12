defmodule Sailor.Stream do
  alias Sailor.Stream.Message

  require Logger

  defstruct [
    identifier: nil,
    sequence: 0,
    unsaved_messages: []
  ]

  def empty?(stream) do
    stream.sequence == 0 && Enum.empty?(stream.unsaved_messages)
  end

  def persist!(db, stream) do
    Logger.debug "Persisting stream for #{stream.identifier} with sequence #{stream.sequence}"

    rows = Enum.map(stream.unsaved_messages, fn message ->
      [
        message.id,
        message.author,
        message.sequence,
        Message.to_compact_json(message)
      ]
    end)

    Exqlite.transaction(db, fn db ->
      {:ok, stmt} = Exqlite.prepare(db, "insert or ignore into stream_messages (id, author, sequence, json) values (?1, ?2, ?3, ?4)")

      Enum.each(rows, fn row ->
        {:ok, _} = Exqlite.execute(db, stmt, row)
      end)

      %{stream | unsaved_messages: [], }
    end)
  end

  def for_peer(db, identifier) do
    {:ok, %Exqlite.Result{rows: [[sequence: max_seq]]}} = Exqlite.query(db, "select max(sequence) as sequence from stream_messages where author = ?", [identifier])

    %__MODULE__{
      identifier: identifier,
      sequence: max_seq || 0,
      unsaved_messages: [],
    }
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
          unsaved_messages: stream.unsaved_messages ++ [message]
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

  def messages(_stream, _start_seq \\ 0) do
    raise "Unimplemented"
  end
end
