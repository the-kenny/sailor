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

  def ssbencode(proplist) do
    proplist
    |> Sailor.Stream.MessageUtils.fmap()
    |> :jsone.encode([:native_utf8, :native_forward_slash, indent: 2, space: 1, float_format: [{:decimals, 4}, :compact]])
    |> String.replace(~r/{\s+}/, "{}") # hack as :jsone encodes `{}` as `{\n}`
    |> String.replace(~r/\[\s+\]/, "[]") # hack as :jsone encodes `[]` as `[\n]`
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
    |> Sailor.Stream.MessageUtils.fmap()
    |> :jsone.encode([:native_utf8, :native_forward_slash, indent: 0, space: 0])
  end

  defp message_fields(message) do
    if message.legacy_id? do @legacy_message_fields else @message_fields end
  end

  @spec from_history_stream_json(String.t) :: {:ok, %__MODULE__{}}
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

    case verify(message) do
      :ok -> nil
      {:error, err} -> Logger.warn "Message #{message.id} failed to verify: #{err}"
    end

    {:ok, message}
  end

  @spec from_json(String.t) :: {:ok, %__MODULE__{}}
  def from_json(str) do
    proplist = :jsone.decode(str, object_format: :proplist)

    field_list = @message_fields
    |> Enum.map(fn field -> {field, :proplists.get_value(to_string(field), proplist)} end)

    message = %{ struct(__MODULE__, field_list) |
      legacy_id?: legacy_id?(proplist)
    }

    # Add the calculated id to `message`
    message = %{ message | id: calculate_id(message) }

    case verify(message) do
      :ok -> nil
      {:error, err} -> Logger.warn "Message failed to verify: #{err}"
    end

    {:ok, message}
  end

  @spec verify(%__MODULE__{}) :: :ok | {:error, any()}
  def verify(message) do
    id = message.id

    with :ok <- verify_signature(message),
         {:id, ^id} <- {:id, calculate_id(message)}
    do
      :ok
    else
      {:error, :forged} -> {:error, "Invalid signature"}
      {:id, calculated_id} -> {:error, "Invalid ID. Calculated #{calculated_id} received #{message.id}"}
    end
  end

  defp legacy_id?(proplist) do
    case Enum.find_index(proplist, fn {key, _val} -> key == "author" end) do
      1 -> false
      2 -> true
    end
  end

  def verify_signature(message) do
    verify_signature(message, message.author)
  end

  def verify_signature(message, author) do
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

  def calculate_id(message) do
    {:ok, hash} = message
    |> to_id_string()
    |> Salty.Hash.Sha256.hash()

    "%#{Base.encode64(hash)}.sha256"
  end

  def mark_processed!(db, message_id) do
    {:ok, _} = Exqlite.query(db, "update stream_messages set processed = true where id = ?", [message_id])
  end
end
