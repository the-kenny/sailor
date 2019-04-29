defmodule Sailor.Peer do
  use GenServer

  alias Sailor.Boxstream
  require Logger

  defmodule State do
    defstruct [
      socket: nil,
      buffer: <<>>,
      decrypting_boxstream: nil,
      encrypting_boxstream: nil,
    ]
  end

  # TODO: Pass identity as arg

  # Start as a Client peer
  def start_link([socket, identity, {:client, server_pubkey}]) do
    network_identifier = Sailor.Identity.network_identifier
    GenServer.start_link(__MODULE__, [socket, {identity, server_pubkey, network_identifier}])
  end

  # Start as a Server peer
  def start_link([socket, identity, :server]) do
    network_identifier = Sailor.Identity.network_identifier
    GenServer.start_link(__MODULE__, [socket, {identity, network_identifier}])
  end


  def init([socket, handshake_data]) do
    {:ok, %State{socket: socket}, {:continue, {:do_handshake, handshake_data}}}
  end

  defp handle_decryption_result({:error, :missing_data}, state) do
    {:noreply, state}
  end

  defp handle_decryption_result({:ok, boxstream, messages, rest_data}, state) do
    state = %{state |
      buffer: rest_data,
      decrypting_boxstream: boxstream,
    }

    Logger.info "Decrypted messages: #{inspect messages}"

    # Respond with a closing message
    # {:ok, encrypting_boxstream, close_msg} = Boxstream.close(state.encrypting_boxstream)
    # :ok = :gen_tcp.send(state.socket, close_msg)

    # state = %{state | encrypting_boxstream: encrypting_boxstream}

    {:noreply, state}
  end

  def handle_info({:tcp, _socket, data}, state) do

    state = %{state | buffer: state.buffer <> data}
    Logger.debug "Buffer: #{inspect state.buffer}"
    handle_decryption_result(Boxstream.decrypt(state.decrypting_boxstream, state.buffer), state)
  end

  # def handle_info({:tcp_closed, socket}, state) do
  #   {:stop, :normal, nil}
  # end

  def handle_continue({:do_handshake, handshake_data}, state) do
    alias Sailor.Handshake.Keypair
    alias Sailor.Handshake
    alias Sailor.Boxstream

    {:ok, handshake} = Sailor.Peer.Handshake.run(state.socket, handshake_data)
    them = %Keypair{pub: handshake.other_pubkey}
    us = handshake.identity
    Logger.info "Successful handshake between #{Keypair.id(us)} (us) and #{Keypair.id(them)} (them)"

    # {:ok, bytes} = :gen_tcp.recv(state.socket, 0) # Read remaining bytes to clear buffer
    # Logger.debug "Read bytes from socket before switching to active mode: #{inspect bytes}"
    :ok = :inet.setopts(state.socket, [active: true])

    {:ok, encrypt, decrypt} = Boxstream.create(Handshake.boxstream_keys(handshake))

    state = %{state |
      # buffer: bytes,
      buffer: <<>>,
      decrypting_boxstream: decrypt,
      encrypting_boxstream: encrypt,
    }

    {:noreply, state}
  end
end
