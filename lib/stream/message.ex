defmodule Sailor.Stream.Message do
  require Logger

  defstruct [
    id: nil,
    author: nil,
    sequence: nil,
    data: nil,
  ]

  @message_fields [:previous, :author, :sequence, :timestamp, :hash, :content, :signature]

  @message_fields |> Enum.each(fn field ->
    # As the order of fields in a message always stays the same we can use index-access in our proplist.
    # In our getters we use pattern matching with the first part of the key-value tuple to verify we're
    # accessing the correct field

    def unquote(field)(%__MODULE__{} = message) do
      with {unquote(to_string(field)), value} <- :proplists.lookup(unquote(to_string(field)), message.data) do
        value
      else
        _ -> raise "Couldn't access field #{unquote(to_string(field))} in message #{inspect message}"
      end
    end

    def unquote(field)(%__MODULE__{} = message, new_value) do
      _old_value = unquote(field)(message)
      index = Enum.find_index(message.data, fn {key, _} -> key == unquote(to_string(field)) end)
      new = List.replace_at(message, index, {unquote(to_string(field)), new_value})
      %{message | data: new} |> normalize()
    end

  end)

  defp normalize(%__MODULE__{} = message) do
    message
    |> Map.put(:id, id(message))
    |> Map.put(:author, author(message))
    |> Map.put(:sequence, sequence(message))
  end

  def to_signing_string(message_data) do
    :jsone.encode(message_data, [:native_forward_slash, indent: 2, space: 1, float_format: [{:decimals, 20}, :compact]])
  end

  def to_compact_json(message) do
    :jsone.encode(message.data, [:native_forward_slash, indent: 0, space: 0])
  end

  def from_history_stream_json(str) do
    json = :jsone.decode(str, object_format: :proplist)
    incoming_id = :proplists.get_value("key", json)

    message = %__MODULE__{
      id: incoming_id,
      data: :proplists.get_value("value", json)
    } |> normalize()

    with :ok <- valid?(message),
         id = id(message),
         legacy_id = legacy_id(message)
    do
      cond do
        id == legacy_id ->
          Logger.warn "Received message id #{incoming_id} matches legacy id #{legacy_id}"
        id != incoming_id && incoming_id != legacy_id ->
          Logger.warn "Received message id #{incoming_id} matches neither legacy-id #{legacy_id} nor normal id #{id}"
        :else -> nil
      end

      {:ok, message}
    end
  end

  def from_json(str) do
    proplist = :jsone.decode(str, object_format: :proplist)
    message = %__MODULE__{data: proplist} |> normalize()

    with :ok <- valid?(message)
    do
      {:ok, message}
    end
  end

  defp valid?(message) do
    try do
      previous(message)
      author(message)
      sequence(message)
      timestamp(message)
      hash(message)
      content(message)
      signature(message)
      :ok
    rescue
      _ -> {:error, :invalid}
    end
  end

  defp signature_string(message) do
    :proplists.delete("signature", message.data)
    |> to_signing_string()
  end

  def add_signature(message, signing_keypair) do
    json = signature_string(message)
    {:ok, signature} = Salty.Sign.Ed25519.sign_detached(json, signing_keypair.sec);
    signature = "#{Base.encode64(signature)}.sig.ed25519"

    message = signature(message, signature)
    {:ok, message}
  end

  def verify_signature(%__MODULE__{} = message, author) do
    {:ok, identity} = Sailor.Keypair.from_identifier(author)
    encoded_signature = signature(message)

    if !String.ends_with?(encoded_signature, ".sig.ed25519") do
      Logger.error "Unsupported signature scheme in #{encoded_signature}"
    end

    signature = encoded_signature
    |> String.replace_suffix(".sig.ed25519", "")
    |> Base.decode64!()

    Salty.Sign.Ed25519.verify_detached(
      signature,
      signature_string(message),
      identity.pub
    )
  end

  def verify_signature(message) do
    verify_signature(message, author(message))
  end

  def id(message) do
    {:ok, hash} = to_signing_string(message)
    |> Salty.Hash.Sha256.hash()

    "%#{Base.encode64(hash)}.sha256"
  end

  def legacy_id(message) do
    raw = message.data
    author = :proplists.lookup("author", raw)
    sequence = :proplists.lookup("sequence", raw)

    {:ok, hash} = raw
    |> List.replace_at(1, sequence)
    |> List.replace_at(2, author)
    |> to_signing_string()
    |> Salty.Hash.Sha256.hash()

    "%#{Base.encode64(hash)}.sha256"
  end

  def all() do
    all(:infinity)
  end

  def all(:ininity) do
    all(-1)
  end

  # TODO
  def all(limit) do
    Sailor.Db.with_db(fn db ->
      {:ok, rows} = Sqlitex.query(db, "select json from stream_messages limit ?", bind: [ limit ])
      rows |> Enum.map(&from_json/1) |> Enum.map(fn {:ok, message} -> message end)
    end)
  end
end
