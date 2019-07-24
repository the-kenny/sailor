defmodule Sailor.Stream.Message do
  require Logger

  # TODO: Store `swapped?` flag to decide which ID to use
  defstruct [
    previous: nil,
    author: nil,
    sequence: nil,
    timestamp: nil,
    hash: nil,
    content: nil,
    signature: nil,

    id: nil,
    legacy_id?: false,
  ]

  @message_fields [:previous, :author, :sequence, :timestamp, :hash, :content, :signature]
  @legacy_message_fields [:previous, :sequence, :author, :timestamp, :hash, :content, :signature]

  # @message_fields |> Enum.each(fn field ->
  #   # As the order of fields in a message always stays the same we can use index-access in our proplist.
  #   # In our getters we use pattern matching with the first part of the key-value tuple to verify we're
  #   # accessing the correct field

  #   def unquote(field)(%__MODULE__{} = message) do
  #     with {unquote(to_string(field)), value} <- :proplists.lookup(unquote(to_string(field)), message.data) do
  #       value
  #     else
  #       _ -> raise "Couldn't access field #{unquote(to_string(field))} in message #{inspect message}"
  #     end
  #   end

  #   def unquote(field)(%__MODULE__{} = message, new_value) do
  #     _old_value = unquote(field)(message)
  #     index = Enum.find_index(message.data, fn {key, _} -> key == unquote(to_string(field)) end)
  #     new = List.replace_at(message, index, {unquote(to_string(field)), new_value})
  #     %{message | data: new} |> normalize()
  #   end

  # end)

  # defp normalize(%__MODULE__{} = message) do
  #   message
  #   |> Map.put(:id, id(message))
  #   |> Map.put(:author, author(message))
  #   |> Map.put(:sequence, sequence(message))
  #   |> Map.put(:legacy_id?, legacy_id?(message.data))
  # end

  defp ssbencode(proplist) do
    proplist
    |> :jsone.encode([:native_utf8, :native_forward_slash, indent: 2, space: 1, float_format: [{:decimals, 4}, :compact]])
    |> String.replace(~r/{\s+}/, "{}") # hack as :jsone encodes `{}` as `{\n}`
  end

  def to_signature_string(message) do
    message_fields(message)
    |> Enum.reject(fn k -> k == :signature end)
    |> Enum.map(fn field -> {to_string(field), Map.get(message, field)} end)
    |> ssbencode()
  end

  def to_id_string(message) do
    message_fields(message)
    |> Enum.map(fn field -> {to_string(field), Map.get(message, field)} end)
    |> ssbencode()
    |> :unicode.characters_to_list(:utf8)
    |> :unicode.characters_to_binary(:utf8, {:utf16, :big})
    |> :binary.bin_to_list()
    |> Enum.drop(1)
    |> Enum.take_every(2)
    |> :binary.list_to_bin()
  end

  def to_compact_json(message) do
    message_fields(message)
    |> Enum.map(fn field -> {to_string(field), Map.get(message, field)} end)
    |> :jsone.encode([:native_utf8, :native_forward_slash, indent: 0, space: 0])
  end

  defp message_fields(message) do
    if message.legacy_id? do @legacy_message_fields else @message_fields end
  end

  def from_history_stream_json(str) do
    outer_proplist = :jsone.decode(str, object_format: :proplist)
    incoming_id = :proplists.get_value("key", outer_proplist)

    proplist = :proplists.get_value("value", outer_proplist)
    field_list = @message_fields
    |> Enum.map(fn field -> {field, :proplists.get_value(to_string(field), proplist)} end)

    message = %{ struct(__MODULE__, field_list) |
      id: incoming_id,
      legacy_id?: legacy_id?(proplist)
    }

    calculated_id = calculate_id(message)

    cond do
      verify_signature(message) != :ok ->
        {:error, "Signature verification failed for message #{incoming_id}"}
      incoming_id != calculated_id ->
        {:error, "Invalid ID: Calculated #{calculated_id}, expected #{incoming_id}"}
      :else ->
        {:ok, message}
    end
  end

  def from_json(str) do
    proplist = :jsone.decode(str, object_format: :proplist)

    field_list = @message_fields
    |> Enum.map(fn field -> {field, :proplists.get_value(to_string(field), proplist)} end)

    message = %{ struct(__MODULE__, field_list) |
      legacy_id?: legacy_id?(proplist)
    }

    # Add the calculated id to `message`
    message = %{ message | id: calculate_id(message) }

    if verify_signature(message) != :ok do
      {:error, "Signature verification failed for message #{message.id}"}
    else
      {:ok, message}
    end
  end

  defp legacy_id?(proplist) do
    case Enum.find_index(proplist, fn {key, _val} -> key == "author" end) do
      1 -> false
      2 -> true
    end
  end

  # defp valid?(message) do
  #   try do
  #     previous(message)
  #     author(message)
  #     sequence(message)
  #     timestamp(message)
  #     hash(message)
  #     content(message)
  #     signature(message)
  #     :ok
  #   rescue
  #     _ -> {:error, :invalid}
  #   end
  # end

  # defp signature_string(message) do
  #   :proplists.delete("signature", message.data)
  #   |> to_signature_string()
  # end

  # def add_signature(message, signing_keypair) do
  #   json = signature_string(message)
  #   {:ok, signature} = Salty.Sign.Ed25519.sign_detached(json, signing_keypair.sec)
  #   signature = "#{Base.encode64(signature)}.sig.ed25519"

  #   message = signature(message, signature)
  #   {:ok, message}
  # end

  def verify_signature(%__MODULE__{} = message, author) do
    {:ok, identity} = Sailor.Keypair.from_identifier(author)

    if !String.ends_with?(message.signature, ".sig.ed25519") do
      Logger.error "Unsupported signature scheme in #{message.signature}"
    end

    signature = message.signature
    |> String.replace_suffix(".sig.ed25519", "")
    |> Base.decode64!()

    Salty.Sign.Ed25519.verify_detached(
      signature,
      to_signature_string(message),
      identity.pub
    )
  end

  def verify_signature(message) do
    verify_signature(message, message.author)
  end

  def calculate_id(message) do
    {:ok, hash} = message
    |> to_id_string()
    |> Salty.Hash.Sha256.hash()

    "%#{Base.encode64(hash)}.sha256"
  end

  # def legacy_id(message) do
  #   raw = message.data
  #   author = :proplists.lookup("author", raw)
  #   sequence = :proplists.lookup("sequence", raw)

  #   {:ok, hash} = raw
  #   |> List.replace_at(1, sequence)
  #   |> List.replace_at(2, author)
  #   |> to_signature_string()
  #   |> Salty.Hash.Sha256.hash()

  #   "%#{Base.encode64(hash)}.sha256"
  # end

  # def all() do
  #   all(:infinity)
  # end

  # def all(:infinity) do
  #   all(-1)
  # end

  # # TODO
  # def all(limit) do
  #   {:ok, rows} = Sailor.Db.with_db(fn db ->
  #     Sqlitex.query(db, "select json from stream_messages limit ?", bind: [ limit ])
  #   end)

  #   rows |> Stream.map(&Keyword.get(&1, :json)) |> Stream.map(&from_json/1) |> Enum.map(fn {:ok, message} -> message end)
  # end

  def mark_processed!(db, message_id) do
    {:ok, _} = Sqlitex.query(db, "update stream_messages set processed = true where id = ?", bind: [message_id])
  end
end
