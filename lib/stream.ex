defmodule Sailor.Stream do
  alias Sailor.Stream.Message

  def for_peer(identifier) do
    {:ok, stream} = Memento.transaction fn ->
      Memento.Query.select(Message, [{:==, :author, identifier}]) |> validate()
    end
    stream
  end

  @doc """

  """
  def extract_peers(stream) do
    stream
    |> Stream.map(&Message.content/1)
    |> Stream.reject(&is_binary/1)
    |> Stream.map(&:proplists.get_value("text", &1, nil))
    |> Stream.filter(&is_binary/1)
    |> Stream.flat_map(&Sailor.Utils.extract_identifiers/1)
  end

  defp validate(stream) do
    stream = stream |> Enum.sort_by(&Message.sequence/1)
    seq_check_result = Enum.map(stream, &Message.sequence/1)
    |> Enum.reduce(1, fn expected, got ->
      if expected == got do
        got + 1
      else
        {:halt, expected, got}
      end
    end)

    case seq_check_result do
      n when is_number(n) -> stream
      {:error, expected, got} ->
        raise "Invalid Sequence. Expected #{expected} got #{got}"
    end
  end
end
