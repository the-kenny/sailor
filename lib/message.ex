# TODO: Support switched `author` and `sequence` fields (ugh)

defmodule Sailor.Message do
  require Logger

  @message_fields [:previous, :author, :sequence, :timestamp, :hash, :content, :signature]

  @message_fields |> Enum.each(fn field ->
    # As the order of fields in a message always stays the same we can use index-access in our proplist.
    # In our getters we use pattern matching with the first part of the key-value tuple to verify we're
    # accessing the correct field

    def unquote(field)({__MODULE__, message}) do
      {unquote(to_string(field)), value} = :proplists.lookup(unquote(to_string(field)), message)
      value
    end

    def unquote(field)({__MODULE__, message}, new_value) do
      _old_value = unquote(field)({__MODULE__, message})
      index = Enum.find_index(message, fn {key, _} -> key == unquote(to_string(field)) end)
      new = List.replace_at(message, index, {unquote(to_string(field)), new_value})
      {__MODULE__, new}
    end

  end)

  defp to_json_string(raw) when is_list(raw) do
    :jsone.encode(raw, indent: 2, space: 1)
    |> String.replace("\\/", "/") # Hack as jsone escapes `/` with `\/`
  end

  def to_json({__MODULE__, raw}) do
    :jsone.encode(raw, indent: 0, space: 0)
    |> String.replace("\\/", "/") # Hack as jsone escapes `/` with `\/`
  end

  def from_json(str) do
    list = :jsone.decode(str, object_format: :proplist)
    # If we get a json string with `key` and `value` (as from `createHistoryStream`) we validate if
    # the computed and the received message IDs are equal and raise if not. Otherwise we just return
    # the message.
    list = case :proplists.get_value("key", list) do
      :undefined -> list
      message_id ->
        list = :proplists.get_value("value", list)
        id = id({__MODULE__, list})
        if id != message_id do
          # raise RuntimeError, message: "Received message id #{message_id} is not equal to computed message id #{id}"
          Logger.error "Received message id #{message_id} is not equal to computed message id #{id}"
        end
        list
    end
    {:ok, {__MODULE__, list}}
  end

  defp signature_string({__MODULE__, message}) do
    :proplists.delete("signature", message)
    |> to_json_string()
  end

  def add_signature(message, signing_keypair) do
    json = signature_string(message)
    {:ok, signature} = Salty.Sign.Ed25519.sign_detached(json, signing_keypair.sec);
    signature = "#{Base.encode64(signature)}.sig.ed25519"

    message = signature(message, signature)
    {:ok, message}
  end

  def verify_signature(message, identity) do
    {:ok, signature} = signature(message)
    |> String.replace_suffix(".sig.ed25519", "")
    |> Base.decode64()

    Salty.Sign.Ed25519.verify_detached(
      signature,
      signature_string(message),
      identity.pub
    )
  end

  defp hash_string(message) do
    to_json_string(message)
  end

  def id({__MODULE__, message}) do
    {:ok, hash} = hash_string(message)
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
