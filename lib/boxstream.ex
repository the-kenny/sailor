# TODO: We might be able to implement this as a Stream via `Stream.transform`: https://hexdocs.pm/elixir/Stream.html

defmodule Sailor.Boxstream do
  require Bitwise

  # alias Salty.Secretbox.primitive, as: Box
  alias Salty.Secretbox.Xsalsa20poly1305, as: Box

  defstruct [
    shared_secret: nil,
    box_key: nil,
    nonce: nil,
  ]


  def create(keys) do
    encrypt = %__MODULE__{
      shared_secret: keys.shared_secret,
      box_key: keys.encrypt_key,
      nonce: keys.encrypt_nonce,
    }

    decrypt = %__MODULE__{
      shared_secret: keys.shared_secret,
      box_key: keys.decrypt_key,
      nonce: keys.decrypt_nonce,
    }

    {:ok, encrypt, decrypt}
  end

  # TODO: Automatic chunking
  def encrypt(_boxstream, msg) when byte_size(msg) > 4096 do
    {:error, "msg > 4096 bytes"}
  end

  def encrypt(boxstream, msg) do
    body_nonce = inc_nonce(boxstream.nonce)
    header_nonce = boxstream.nonce
    {:ok, <<secret_box2 :: bytes-size(16), encrypted_body :: binary>>} = Box.seal(
      msg,
      body_nonce,
      boxstream.shared_secret
    )
    16 = byte_size(secret_box2)

    header = <<byte_size(encrypted_body) :: size(16)>> <> secret_box2

    {:ok, secret_box1} = Box.seal(
      header,
      header_nonce,
      boxstream.shared_secret
    )

    34 = byte_size(secret_box1)

    encrypted_message = secret_box1 <> encrypted_body

    {:ok, %{boxstream | nonce: inc_nonce(body_nonce)}, encrypted_message}
  end

  @close_header :binary.copy(<<0>>, 18)

  def close(boxstream) do
    header_nonce = boxstream.nonce

    {:ok, encrypted_header} = Box.seal(
      @close_header,
      header_nonce,
      boxstream.shared_secret
    )

    {:ok, %{boxstream | nonce: inc_nonce(header_nonce)}, encrypted_header}
  end

  def decrypt(boxstream, msg) do
    header_nonce = boxstream.nonce
    body_nonce = inc_nonce(boxstream.nonce)

    <<secret_box1 :: bytes-size(34), rest :: binary>> = msg
    {:ok, header} = Box.open(
      secret_box1,
      header_nonce,
      boxstream.shared_secret
    )

    if header == @close_header do
      :closed
    else
      <<body_length :: size(16), secret_box2 :: bytes-size(16)>> = header
      if byte_size(rest) < body_length do
        {:error, :missing_data}
      else
        <<body :: bytes-size(body_length), rest :: binary>> = rest
        {:ok, plaintext_body} = Box.open(
          secret_box2 <> body,
          body_nonce,
          boxstream.shared_secret
        )

        boxstream = %{boxstream | nonce: inc_nonce(body_nonce)}

        {:ok, boxstream, plaintext_body, rest}
      end
    end
  end

  def inc_nonce(nonce) do
    n = :binary.decode_unsigned(nonce)

    new_nonce = :binary.encode_unsigned(n+1)
    if byte_size(new_nonce) > byte_size(nonce) do
      :binary.copy(<<0>>, byte_size(nonce))
    else
      # Pad `new-nonce` to the size of `nonce`
      :binary.copy(<<0>>, byte_size(nonce) - byte_size(new_nonce)) <> new_nonce
    end
  end
end
