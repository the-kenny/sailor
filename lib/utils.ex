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
    Regex.run(~r(&[a-zA-Z0-9\+/=]+\.sha256), str) || []
  end

end
