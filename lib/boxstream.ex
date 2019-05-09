# TODO: We might be able to implement this as a Stream via `Stream.transform`: https://hexdocs.pm/elixir/Stream.html

require Stream

defmodule Sailor.Boxstream do
  require Bitwise

  # alias Salty.Secretbox.primitive, as: Box
  alias Salty.Secretbox.Xsalsa20poly1305, as: Box

  defstruct [
    shared_secret: nil,
    nonce: nil,
  ]

  def create(keys) do\
    encrypt = %__MODULE__{
      shared_secret: keys.encrypt_key,
      nonce: keys.encrypt_nonce,
    }

    decrypt = %__MODULE__{
      shared_secret: keys.decrypt_key,
      nonce: keys.decrypt_nonce,
    }

    {:ok, encrypt, decrypt}
  end

  # TODO: Automatic chunking
  def encrypt(_boxstream, chunk) when byte_size(chunk) > 4096 do
    {:error, "chunk > 4096 bytes"}
  end

  def encrypt(boxstream, chunk) do
    body_nonce = inc_nonce(boxstream.nonce)
    header_nonce = boxstream.nonce
    {:ok, <<secret_box2 :: bytes-size(16), encrypted_body :: binary>>} = Box.seal(
      chunk,
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

  def decrypt(boxstream, buffer, chunks \\ []) do
    case decrypt_chunk(boxstream, buffer) do
      :closed -> {:closed, chunks}
      {:error, :missing_data} -> {:ok, boxstream, chunks, buffer}
      {:ok, boxstream, chunk, rest} -> decrypt(boxstream, rest, chunks ++ [chunk])
    end
  end

  @spec decrypt_chunk(any(), binary) :: :closed | {:error, term()} | {:ok, any(), binary(), binary()}

  def decrypt_chunk(_boxstream, chunk) when byte_size(chunk) < 34 do
    {:error, :missing_data}
  end

  def decrypt_chunk(boxstream, chunk) do
    header_nonce = boxstream.nonce
    body_nonce = inc_nonce(boxstream.nonce)

    <<secret_box1 :: bytes-size(34), rest :: binary>> = chunk
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
        {:ok, chunk} = Box.open(
          secret_box2 <> body,
          body_nonce,
          boxstream.shared_secret
        )

        boxstream = %{boxstream | nonce: inc_nonce(body_nonce)}

        {:ok, boxstream, chunk, rest}
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

# TODO: Correctly handle closed socket
defmodule Sailor.Boxstream.IO do
  use GenServer

  alias Sailor.Boxstream
  alias Sailor.Handshake

  defstruct [
    socket: nil,
    boxstream: nil,
    recv_buffer: nil,
    decrypted_data: nil,
  ]

  def open(socket, handshake) do
    {:ok, encrypt, decrypt} = Boxstream.create(Handshake.boxstream_keys(handshake))
    {:ok, reader} = reader(socket, decrypt);
    {:ok, writer} = writer(socket, encrypt);

    {:ok, reader, writer}
  end


  # TODO: Is socket ownership handled correctly here?
  def reader(socket, boxstream) do
    GenServer.start(__MODULE__, [socket, boxstream])
  end

  def writer(socket, boxstream) do
    GenServer.start(__MODULE__, [socket, boxstream])
  end

  def init([socket, boxstream]) do
    state = %__MODULE__{
      socket: socket,
      boxstream: boxstream,
      recv_buffer: <<>>,
      decrypted_data: <<>>,
    }

    {:ok, state}
  end

  defp read_available(state) do
    with {:ok, data} <- :gen_tcp.recv(state.socket, 0)
    do
      recv_buffer = state.recv_buffer <> data
      {:ok, %{state | recv_buffer: recv_buffer}}
    end
  end

  defp decrypt_available(state) do
    # TODO: Handle `{:closed, chunks}` and `{:error, :missing_data}`.
    # We have to propagate closed and can just ignore `:missing_data`
    # as this function is automatically called in a loop
    case Boxstream.decrypt(state.boxstream, state.recv_buffer) do
      {:closed, chunks} ->
        state = %{state | decrypted_data: state.decrypted_data <> :erlang.iolist_to_binary(chunks)}
        {:ok, state}
      {:error, :missing_data} -> {:ok, state}
      {:ok, boxstream, chunks, rest} ->
        state = %{state |
          boxstream: boxstream,
          recv_buffer: rest,
          decrypted_data: state.decrypted_data <> :erlang.iolist_to_binary(chunks),
        }
        {:ok, state}
    end
  end

  # Invalid request, n < 0
  defp io_read(from, reply_as, bytes_requested, state) when bytes_requested < 0 do
    :ok = Process.send(from, {:io_reply, reply_as, {:error, :badarg}}, [])
    {:noreply, state}
  end

  # We have enough decrypted data in `state.decrypted_data`
  defp io_read(from, reply_as, bytes_requested, %{decrypted_data: available} = state) when bytes_requested <= byte_size(available) do
    <<response :: binary-size(bytes_requested), rest :: binary>> = state.decrypted_data
    :ok = Process.send(from, {:io_reply, reply_as, response}, [])
    {:noreply, %{state | decrypted_data: rest}}
  end

  # Read more data from `state.socket` and try to decrypt
  defp io_read(from, reply_as, bytes_requested, state) do
    with {:ok, state} <- read_available(state),
         {:ok, state} <- decrypt_available(state)
    do
      io_read(from, reply_as, bytes_requested, state)
    else
      # TODO: Handle graceful close by signalling EOF
      # {:closed, chunks} ->
      #   # Boxstream closed, graceful exit
      #   :ok = Process.send(from, {:io_reply, reply_as, :eof}, [])
      #   {:stop, {:error, :closed}, state}
      err ->
        :ok = Process.send(from, {:io_reply, reply_as, err}, [])
        {:stop, err, state}
    end
  end

  def handle_info({:io_request, from, reply_as, {:get_chars, :"", n}}, state), do: io_read(from, reply_as, n, state)
  def handle_info({:io_request, from, reply_as, {:get_chars, _encoding, :"", n}}, state), do: io_read(from, reply_as, n, state)

  def handle_info({:io_request, from, reply_as, {:put_chars, _encoding, data}}, state) do
    with {:ok, boxstream, message} <- Boxstream.encrypt(state.boxstream, data),
         :ok <- :gen_tcp.send(state.socket, message)
    do
      Process.send(from, {:io_reply, reply_as, :ok}, [])
      {:noreply, %{state | boxstream: boxstream}}
    else
      {:error, err} ->
        Process.send(from, {:io_reply, reply_as, {:error, err}}, [])
        {:noreply, state}
    end
  end
end
