# TODO: Support switched `author` and `sequence` fields (ugh)

defmodule Sailor.Message do
  require Logger

  @message_fields [:previous, :author, :sequence, :timestamp, :hash, :content, :signature]

  @message_fields |> Enum.each(fn field ->
    # As the order of fields in a message always stays the same we can use index-access in our proplist.
    # In our getters we use pattern matching with the first part of the key-value tuple to verify we're
    # accessing the correct field

    def unquote(field)({__MODULE__, message}) do
      with {unquote(to_string(field)), value} <- :proplists.lookup(unquote(to_string(field)), message) do
        value
      else
        _ -> raise "Couldn't access field #{unquote(to_string(field))} in message #{inspect message}"
      end
    end

    def unquote(field)({__MODULE__, message}, new_value) do
      _old_value = unquote(field)({__MODULE__, message})
      index = Enum.find_index(message, fn {key, _} -> key == unquote(to_string(field)) end)
      new = List.replace_at(message, index, {unquote(to_string(field)), new_value})
      {__MODULE__, new}
    end

  end)

  def to_signing_string({__MODULE__, raw}) do
    :jsone.encode(raw, [:native_forward_slash, indent: 2, space: 1, float_format: [{:decimals, 20}, :compact]])
  end

  def to_json({__MODULE__, raw}) do
    :jsone.encode(raw, [:native_forward_slash, indent: 0, space: 0])
  end

  def from_history_stream_json(str) do
    json = :jsone.decode(str, object_format: :proplist)
    message_id = :proplists.get_value("key", json)
    message = {__MODULE__, :proplists.get_value("value", json)}


    with :ok <- valid?(message),
         id = id(message),
         legacy_id = legacy_id(message)
    do
      cond do
        id == legacy_id ->
          Logger.warn "Received message id #{message_id} matches legacy id #{legacy_id}"
        id != message_id && id != legacy_id ->
          Logger.warn "Received message id #{message_id} matches neither legacy-id #{legacy_id} nor normal id #{id}"
        :else -> nil
      end

      {:ok, message}
    end
  end

  def from_json(str) do
    with message = {__MODULE__, :jsone.decode(str, object_format: :proplist)},
         :ok <- valid?(message)
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

  defp signature_string({__MODULE__, message}) do
    to_signing_string({__MODULE__, :proplists.delete("signature", message)})
  end

  def add_signature(message, signing_keypair) do
    json = signature_string(message)
    {:ok, signature} = Salty.Sign.Ed25519.sign_detached(json, signing_keypair.sec);
    signature = "#{Base.encode64(signature)}.sig.ed25519"

    message = signature(message, signature)
    {:ok, message}
  end

  def verify_signature(message, author) do
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

  defp hash_string(message) do
    to_signing_string(message)
  end

  def id(message) do
    {:ok, hash} = hash_string(message)
    |> Salty.Hash.Sha256.hash()

    "%#{Base.encode64(hash)}.sha256"
  end

  def legacy_id({__MODULE__, raw}) do
    author = :proplists.lookup("author", raw)
    sequence = :proplists.lookup("sequence", raw)

    raw = raw
    |> List.replace_at(1, sequence)
    |> List.replace_at(2, author)

    {:ok, hash} = hash_string({__MODULE__, raw})
    |> Salty.Hash.Sha256.hash()

    "%#{Base.encode64(hash)}.sha256"
  end


  @behaviour Sailor.Database.Storable

  def to_record(message) do
    {
      __MODULE__,
      Sailor.Message.id(message),
      Sailor.Message.author(message),
      Sailor.Message.timestamp(message),
      message
    }
  end

  def from_record({__MODULE__, _id, _author, _timestamp, message}) do
    message
  end
end

# defimpl Sailor.Database.Storable, for: Sailor.Message do
#   def to_db_tuple(message) do
#     {
#       Message,
#       Sailor.Message.id(message),
#       Sailor.Message.author(message),
#       Sailor.Message.timestamp(message),
#       message
#     }
#   end

#   def from_db_tuple({Message, _id, _author, _timestamp, message}) do
#     message
#   end
# end
