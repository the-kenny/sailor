defmodule Sailor.Message do
  defstruct [
    previous: nil,
    author: nil,
    sequence: nil,
    timestamp: nil,
    hash: "sha256",
    content: %{},
    signature: nil,

    raw: nil,
  ]

  [:previous, :author, :sequence, :timestamp, :hash, :content, :signature] |> Enum.with_index() |> Enum.each(fn {field, idx} ->
    def unquote(field)(message) do
      # :proplists.get_value(message, to_string(field))
      Enum.at(message, unquote(idx))
    end

    def unquote(field)(message, new_value) do
      List.replace_at(message, unquote(idx), new_value)
    end

  end)

  defp raw_to_json(raw) do
    :jsone.encode(raw, indent: 2, space: 1)
    |> String.replace("\\/", "/") # Hack as jsone escapes `/` with `\/`
  end

  defp raw_to_message(raw) do
    Enum.reduce(raw, %__MODULE__{raw: raw}, fn ({key, value}, acc) ->
      value = if key == "content" do
        Map.new(elem(value, 0))
      else
        value
      end
      Map.put(acc, String.to_atom(key), value)
    end)
  end

  defp message_to_raw(message) do
    :unimplemented
  end

  def from_json(str) do
    {list} = :jsone.decode(str, object_format: :tuple)
    {:ok, raw_to_message(list)}
  end

  defp signature_string(message) do
    :proplists.delete("signature", message.raw)
    |> raw_to_json()
  end

  def add_signature(message, signing_keypair) do
    json = signature_string(message)
    {:ok, signature} = Salty.Sign.Ed25519.sign_detached(json, signing_keypair.sec);
    signature = "#{Base.encode64(signature)}.sig.ed25519"

    raw = message.raw |> Keyword.delete(:signature)
    message = %{message |
      signature: signature,
      raw: raw ++ [{:signature, signature}]
    }
    {:ok, message}
  end

  def verify_signature(message, identity) do
    {:ok, signature} = message.signature
    |> String.replace_suffix(".sig.ed25519", "")
    |> Base.decode64()

    Salty.Sign.Ed25519.verify_detached(
      signature,
      signature_string(message),
      identity.pub
    )
  end

  defp hash_string(message) do
    raw_to_json(message.raw)
  end

  def message_id(message) do
    {:ok, hash} = hash_string(message)
    |> Salty.Hash.Sha256.hash()

    {:ok, "%#{Base.encode64(hash)}.sha256"}
  end
end
