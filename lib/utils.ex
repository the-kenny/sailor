defmodule Sailor.Utils do

  @doc """
  Extracts all Scuttlebutt identifiers from `str`
  """
  def extract_identifiers(str) do
    Regex.run(~r(@[a-zA-Z0-9\+/=]+\.ed25519), str) || []
  end

  @doc """
  Extracts all Scuttlebutt blob references from `str`
  """
  def extract_blobs(str) do
    (Regex.run(~r(&[a-zA-Z0-9\+/=]+\.sha256), str) || [])
    |> Enum.filter(&Sailor.Blob.valid?/1)
  end

  def message_blobs(message) do
    [message]
    |> Stream.map(&Map.get(&1, :content))
    |> Stream.reject(&is_binary/1)
    |> Stream.map(&:proplists.get_value("text", &1, nil))
    |> Stream.filter(&is_binary/1)
    |> Enum.flat_map(&extract_blobs/1)
  end

end
