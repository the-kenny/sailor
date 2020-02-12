defmodule Sailor.Blob do
  @max_size 1024 * 1024 * 5

  def valid?(blob) do
    case hash_binary(blob) do
      {:ok, _} -> true
      _ -> false
    end
  end

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

  defp hash_binary(blob) do
    blob
    |> String.trim_leading("&")
    |> String.trim_trailing(".sha256")
    |> Base.decode64()
  end

  def path(blob) do
    {:ok, binary} = hash_binary(blob)

    id = binary
    |> Base.encode16()
    |> String.downcase()

    dir = String.slice(id, 0..1)
    Path.join([@base_path, dir, id])
  end

  def available?(blob) do
    File.exists?(path(blob))
  end

  def persist!(binary) do
    {:ok, blob} = from_binary(binary)
    path = path(blob)
    :ok = File.mkdir_p(Path.dirname(path))
    File.write!(path(blob), binary)
  end

  def persist_file!(path) do
    {:ok, blob} = from_file(path)
    blob_path = path(blob)
    :ok = File.mkdir_p(Path.dirname(blob_path))
    File.cp!(path, blob_path)
  end

  # Database Operations

  def mark_wanted!(db, blob, severity) do
    case Exqlite.query(db, "insert or ignore into wanted_blobs (blob, severity) values (?, ?)", [blob, severity]) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  def remove_wanted!(db, blob) do
    {:ok, _} = Exqlite.query(db, "delete from wanted_blobs where blob = ?", [blob])
    :ok
  end

  def all_wanted(db) do
    {:ok, result} = Exqlite.query(db, "select blob, severity from wanted_blobs order by severity desc")

    result.rows
    |> Stream.map(fn [blob: blob, severity: severity] -> {blob, severity} end)
    |> Enum.into(%{}, fn entry -> entry end)
  end
end
