defmodule Sailor.Utils do

  @doc """
  Extracts all Scuttlebutt identifiers from a given string
  """
  def extract_identifiers(str) do
    Regex.run(~r(@[a-zA-Z0-9\+/=]+\.ed25519), str) || []
  end

  def extract_blobs() do

  end

end
