defmodule Sailor.Peer do
  use GenServer

  alias Sailor.Boxstream
  require Logger

  defmodule State do
    defstruct [
    ]
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, [])
  end

  # Start as a Client peer
  def run(peer, socket, identity, {:client, server_pubkey}) do
    network_identifier = Sailor.Identity.network_identifier
    :ok = :gen_tcp.controlling_process(socket, peer)
    :ok = GenServer.cast(peer, {:do_handshake, socket, {identity, server_pubkey, network_identifier}})
    :ok
  end

  # Start as a Server peer
  def run(peer, socket, identity, :server) do
    network_identifier = Sailor.Identity.network_identifier
    :ok = :gen_tcp.controlling_process(socket, peer)
    :ok = GenServer.cast(peer, {:do_handshake, socket, {identity, network_identifier}})
    :ok
  end

  # Callbacks

  def init([]) do
    {:ok, %State{}}
  end

  def handle_cast({:initialize, socket}, state) do
    {:noreply, %{state | socket: socket}}
  end

  # defp handle_decryption_result({:error, :missing_data}, state) do
  #   {:noreply, state}
  # end

  # defp handle_decryption_result({:ok, boxstream, messages, rest_data}, state) do
  #   state = %{state |
  #     buffer: rest_data,
  #     decrypting_boxstream: boxstream,
  #   }

  #   Logger.info "Decrypted messages: #{inspect messages}"

  #   # Respond with a closing message
  #   # {:ok, encrypting_boxstream, close_msg} = Boxstream.close(state.encrypting_boxstream)
  #   # :ok = :gen_tcp.send(state.socket, close_msg)

  #   # state = %{state | encrypting_boxstream: encrypting_boxstream}

  #   {:noreply, state}
  # end

  # def handle_info({:tcp, _socket, data}, state) do

  #   state = %{state | buffer: state.buffer <> data}
  #   Logger.debug "Buffer: #{inspect state.buffer}"
  #   handle_decryption_result(Boxstream.decrypt(state.decrypting_boxstream, state.buffer), state)
  # end

  # def handle_info({:tcp_closed, socket}, state) do
  #   {:stop, :normal, nil}
  # end

  def handle_cast({:do_handshake, socket, handshake_data}, state) do
    alias Sailor.Handshake.Keypair
    alias Sailor.Handshake
    alias Sailor.Boxstream

    {:ok, handshake} = Sailor.Peer.Handshake.run(socket, handshake_data)
    them = %Keypair{pub: handshake.other_pubkey}
    us = handshake.identity
    Logger.info "Successful handshake between #{Keypair.id(us)} (us) and #{Keypair.id(them)} (them)"

    # {:ok, bytes} = :gen_tcp.recv(state.socket, 0) # Read remaining bytes to clear buffer
    # Logger.debug "Read bytes from socket before switching to active mode: #{inspect bytes}"
    # :ok = :inet.setopts(state.socket, [active: true])

    {:ok, encrypt, decrypt} = Boxstream.create(Handshake.boxstream_keys(handshake))

    Task.start(fn ->
      {:ok, read} = Sailor.Boxstream.IO.reader(socket, decrypt);
      IO.binstream(read, 1) |> Stream.each(&IO.inspect(&1)) |> Stream.run
    end)


    {:ok, writer} = Sailor.Boxstream.IO.writer(socket, encrypt)
    Task.start(fn -> IO.binwrite(writer, <<"HELLO">>) end)

    # {:ok, _boxstream, message} = Boxstream.encrypt(encrypt, <<"HELLO">>)
    # :ok = :gen_tcp.send(socket, message);

    {:noreply, state}
  end
end
