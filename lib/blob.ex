defmodule Sailor.Blob do
  @max_size 1024 * 1024 * 5

  def from_file(path) do
    {:ok, stat} = File.stat(path)
    if stat.size > @max_size do
      {:error, :too_big}
    else
      from_binary(File.read!(path))
    end
  end

  def from_binary(binary) do
    if byte_size(binary) > @max_size do
      {:error, :too_big}
    else
      hash = :crypto.hash(:sha256, binary)
      {:ok, "&#{Base.encode64(hash)}.sha256"}
    end
  end

  @base_path Path.join(Application.get_env(:sailor, :data_path) , "blobs")

  def path(blob) do
    id = blob |> String.trim_leading("&") |> String.trim_trailing(".sha256")
    dir = String.slice(id, 0..1) |> String.downcase()
    Path.join([@base_path, dir, id])
  end
end
