defmodule Sailor.Message do
  require Logger

  [:previous, :author, :sequence, :timestamp, :hash, :content, :signature] |> Enum.with_index() |> Enum.each(fn {field, idx} ->
    # As the order of fields in a message always stays the same we can use index-access in our proplist.
    # In our getters we use pattern matching with the first part of the key-value tuple to verify we're
    # accessing the correct field

    def unquote(field)(message) do
      {unquote(to_string(field)), value} = Enum.at(message, unquote(idx))
      value
    end

    def unquote(field)(message, new_value) do
      _old_value = unquote(field)(message)
      List.replace_at(message, unquote(idx), {unquote(to_string(field)), new_value})
    end

  end)

  defp to_json_string(raw) do
    :jsone.encode(raw, indent: 2, space: 1)
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
        message = :proplists.get_value("value", list)
        if id(message) != message_id do
          raise RuntimeError, message: "Received message id #{message_id} is not equal to computed message id #{id(message)}"
        end
        message
    end
    {:ok, list}
  end

  defp signature_string(message) do
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

  def id(message) do
    {:ok, hash} = hash_string(message)
    |> Salty.Hash.Sha256.hash()

    "%#{Base.encode64(hash)}.sha256"
  end
end
