require Salty.Auth
require Salty.Box
require Jason

defmodule Sailor.Handshake.Keypair do
  defstruct [:curve, :pub, :sec]

  def from_id(id) do
    with <<"@", pub_base64 :: bytes-size(44), ".", curve :: binary>> <- id,
         {:ok, pub} <- Base.decode64(pub_base64)
    do
      keypair = %__MODULE__{
        curve: String.to_existing_atom(curve),
        pub: pub,
      }

      {:ok, keypair}
    else
      _ -> :error
    end
  end

  def load_secret(path) do
    with {:ok, contents} <- File.read(Path.expand(path)),
         json_str = contents |> String.split("\n") |> Enum.filter(fn s -> !String.starts_with?(s, "#") end) |> Enum.join(),
    do: from_secret(json_str)
  end

  def from_secret(json_str) do
    with {:ok, json} <- Jason.decode(json_str)
    do
      [private_base64, "ed25519"] = String.split(json["private"], ".")
      [public_base64, "ed25519"] = String.split(json["public"], ".")

      keypair = %__MODULE__{
        curve: String.to_atom(json["curve"]),
        sec: Base.decode64!(private_base64),
        pub: Base.decode64!(public_base64),
      }

      {:ok, keypair}
    end
  end

  def to_secret(keypair) do
    base64_pub = Base.encode64 keypair.pub
    base64_sec = Base.encode64 keypair.sec
    curve = to_string keypair.curve
    Jason.encode! %{
      curve: curve,
      public: base64_pub <> "." <> curve,
      private: base64_sec <> "." <> curve,
      id: id(keypair)
    }
  end

  def id(keypair) do
    "@" <> Base.encode64(keypair.pub) <> "." <> to_string keypair.curve
  end

  def random() do
    {:ok, pub, sec} = Salty.Sign.Ed25519.keypair
    true = Salty.Sign.Ed25519.publickeybytes == byte_size(pub)
    true = Salty.Sign.Ed25519.secretkeybytes == byte_size(sec)
    %__MODULE__{curve: :ed25519, pub: pub, sec: sec}
  end

  def randomCurve25519() do
    {:ok, pub, sec} = Salty.Box.primitive.keypair
    true = Salty.Box.primitive.publickeybytes == byte_size(pub)
    true = Salty.Box.primitive.secretkeybytes == byte_size(sec)
    %__MODULE__{curve: :curve25519, pub: pub, sec: sec}
  end
end

defmodule Sailor.Handshake do
  alias Sailor.Handshake.Keypair, as: Keypair
  require Logger

  @appkey Base.decode64!("1KHLiKZvAvjbY1ziZEHMXawbCEIM6qwjCDm3VYRan/s=")

  def default_appkey(), do: @appkey

  defstruct [
    identity: %Keypair{},
    ephemeral: {<<>>, <<>>},
    # TODO: Refactor and use `Keypair` for convenience formatting functions
    other_pubkey: <<>>,
    other_ephemeral: %Keypair{},
    network_identifier: <<>>,

    shared_secret_ab: <<>>,
    shared_secret_aB: <<>>,
    shared_secret_Ab: <<>>,

    detached_signature_a: <<>>,
    detached_signature_b: <<>>,
  ]

  def shared_secret(state) do
    # sha256(
    #   concat(
      #     network_identifier,
      #     shared_secret_ab,
      #     shared_secret_aB,
      #     shared_secret_Ab
      #   )
      # )

    data = state.network_identifier <> state.shared_secret_ab <> state.shared_secret_aB <> state.shared_secret_Ab
    1024 = bit_size(data)

    {:ok, shared_secret} = Salty.Hash.Sha256.hash(data)
    {:ok, shared_secret}
  end

  def create(identity, other_pubkey, network_identifier) do
    %__MODULE__{
      identity: identity,
      ephemeral: Keypair.randomCurve25519(),
      other_pubkey: other_pubkey,
      other_ephemeral: %Keypair{},
      network_identifier: network_identifier,
    }
  end

  def hello_challenge(state) do
    {:ok, nacl_auth} = Salty.Auth.primitive.auth(state.ephemeral.pub, state.network_identifier)
    nacl_auth <> state.ephemeral.pub
  end

  def verify_hello(state, <<msg :: bytes-size(64)>>) do
    <<hmac :: bytes-size(32), other_ephemeral_pub :: bytes-size(32)>> = msg
    :ok = Salty.Auth.primitive.verify(hmac, other_ephemeral_pub, state.network_identifier)
    state = %{state | other_ephemeral: %Keypair{pub: other_ephemeral_pub}}
    {:ok, state}
  end

  def derive_secrets(state) do
    {:ok, shared_secret_ab} = Salty.Scalarmult.Curve25519.scalarmult(state.ephemeral.sec, state.other_ephemeral.pub)

    server? = state.other_pubkey == nil

    # If `other_pubkey` is nil we're on the server (as the client didn't send its pubkey yet)
    {:ok, shared_secret_aB} = if server? do
      # Server:
      # shared_secret_aB = nacl_scalarmult(
      #   sk_to_curve25519(server_longterm_sk),
      #   client_ephemeral_pk
      # )

      {:ok, our_sk_curve25519} = Salty.Sign.Ed25519.crypto_sign_ed25519_sk_to_curve25519(state.identity.sec)
      Salty.Scalarmult.Curve25519.scalarmult(
        our_sk_curve25519,
        state.other_ephemeral.pub
      )

    else
      # shared_secret_aB = nacl_scalarmult(
      #   client_ephemeral_sk,
      #   pk_to_curve25519(server_longterm_pk)
      # )

      {:ok, server_pk_curve25519} = Salty.Sign.Ed25519.crypto_sign_ed25519_pk_to_curve25519(state.other_pubkey)
      Salty.Scalarmult.Curve25519.scalarmult(
        state.ephemeral.sec,
        server_pk_curve25519
      )
    end

    # Calculate detached_signature_a for step 3 'Client Authenticate'
    # detached_signature_A = nacl_sign_detached(
    #   msg: concat(
    #     network_identifier,
    #     server_longterm_pk,
    #     sha256(shared_secret_ab)
    #   ),
    #   key: client_longterm_sk
    # )

    {:ok, %{state |
      shared_secret_ab: shared_secret_ab,
      shared_secret_aB: shared_secret_aB,
    }}
  end

  def client_authenticate(state) do
    # Make sure to run this only on the client
    true = (state.other_pubkey != nil)

    # Some safeguards
    true = (state.shared_secret_ab != nil)
    true = (state.shared_secret_aB != nil)

    {:ok, sha256_shared_secret_ab} = Salty.Hash.Sha256.hash(state.shared_secret_ab)
    {:ok, detached_signature_a} = Salty.Sign.Ed25519.sign_detached(
      state.network_identifier <> state.other_pubkey <> sha256_shared_secret_ab,
      state.identity.sec
    )

    state = %{state | detached_signature_a: detached_signature_a}

    # nacl_secret_box(
    #   msg: concat(
    #     detached_signature_A,
    #     client_longterm_pk
    #   ),
    #   nonce: 24_bytes_of_zeros,
    #   key: sha256(
    #     concat(
    #       network_identifier,
    #       shared_secret_ab,
    #       shared_secret_aB
    #     )
    #   )
    # )
    {:ok, sha256_secretbox_key} = Salty.Hash.Sha256.hash(
      state.network_identifier <> state.shared_secret_ab <> state.shared_secret_aB
    )
    {:ok, message} = Salty.Secretbox.primitive.seal(
      detached_signature_a <> state.identity.pub,
      :binary.copy(<<0>>, 24),
      sha256_secretbox_key
    )

    # Calculate shared_secret_Ab
    # shared_secret_Ab = nacl_scalarmult(
    #   sk_to_curve25519(client_longterm_sk),
    #   server_ephemeral_pk
    # )
    {:ok, our_sk_curve25519} = Salty.Sign.Ed25519.crypto_sign_ed25519_sk_to_curve25519(state.identity.sec)
    {:ok, shared_secret_Ab} = Salty.Scalarmult.Curve25519.scalarmult(
      our_sk_curve25519,
      state.other_ephemeral.pub
    )
    state = %{state | shared_secret_Ab: shared_secret_Ab}

    {:ok, state, message}
  end

  def verify_client_authenticate(state, msg) do
    # Make sure to run this only on the server
    nil = state.other_pubkey

    # Some safeguards
    true = (state.shared_secret_ab != nil)
    true = (state.shared_secret_aB != nil)

    # msg3_plaintext = assert_nacl_secretbox_open(
    #   ciphertext: msg3,
    #   nonce: 24_bytes_of_zeros,
    #   key: sha256(
    #     concat(
    #       network_identifier,
    #       shared_secret_ab,
    #       shared_secret_aB
    #     )
    #   )
    # )

    # assert(length(msg3_plaintext) == 96)

    # detached_signature_A = first_64_bytes(msg3_plaintext)
    # client_longterm_pk = last_32_bytes(msg3_plaintext)

    # assert_nacl_sign_verify_detached(
    #   sig: detached_signature_A,
    #   msg: concat(
    #     network_identifier,
    #     server_longterm_pk,
    #     sha256(shared_secret_ab)
    #   ),
    #   key: client_longterm_pk
    # )

    {:ok, sha256_secretbox_key} = Salty.Hash.Sha256.hash(
      state.network_identifier <> state.shared_secret_ab <> state.shared_secret_aB
    )
    {:ok, msg3_plaintext} = Salty.Secretbox.primitive.open(
      msg,
      :binary.copy(<<0>>, 24),
      sha256_secretbox_key
    )

    96 = byte_size(msg3_plaintext)

    <<detached_signature_a :: bytes-size(64), client_pub :: bytes-size(32)>> = msg3_plaintext

    {:ok, sha256_shared_secret_ab} = Salty.Hash.Sha256.hash(state.shared_secret_ab)
    :ok = Salty.Sign.primitive.verify_detached(
      detached_signature_a,
      state.network_identifier <> state.identity.pub <> sha256_shared_secret_ab,
      client_pub
    )

    # Calculate shared_secret_Ab
    # shared_secret_Ab = nacl_scalarmult(
    #   server_ephemeral_sk,
    #   pk_to_curve25519(client_longterm_pk)
    # )
    {:ok, client_pubkey_curve25519} = Salty.Sign.Ed25519.crypto_sign_ed25519_pk_to_curve25519(client_pub)
    {:ok, shared_secret_Ab} = Salty.Scalarmult.Curve25519.scalarmult(
      state.ephemeral.sec,
      client_pubkey_curve25519
    )
    state = %{state |
      other_pubkey: client_pub,
      detached_signature_a: detached_signature_a,
      shared_secret_Ab: shared_secret_Ab
    }

    {:ok, state}
  end

  def server_accept(state) do
    # detached_signature_B = nacl_sign_detached(
    #   msg: concat(
    #     network_identifier,
    #     detached_signature_A,
    #     client_longterm_pk,
    #     sha256(shared_secret_ab)
    #   ),
    #   key: server_longterm_sk
    # )

    {:ok, sha256_shared_secret_ab} = Salty.Hash.Sha256.hash(state.shared_secret_ab)
    {:ok, detached_signature_b} = Salty.Sign.Ed25519.sign_detached(
      state.network_identifier <> state.detached_signature_a <> state.other_pubkey <> sha256_shared_secret_ab,
      state.identity.sec
    )

    # nacl_secret_box(
    #   msg: detached_signature_B,
    #   nonce: 24_bytes_of_zeros,
    #   key: sha256(
    #     concat(
    #       network_identifier,
    #       shared_secret_ab,
    #       shared_secret_aB,
    #       shared_secret_Ab
    #     )
    #   )
    # )

    {:ok, secretbox_key} = Salty.Hash.Sha256.hash state.network_identifier <> state.shared_secret_ab <> state.shared_secret_aB <> state.shared_secret_Ab
    {:ok, message} = Salty.Secretbox.primitive.seal(
      detached_signature_b,
      :binary.copy(<<0>>, 24),
      secretbox_key
    )

    state = %{state | detached_signature_b: detached_signature_b}
    {:ok, state, message}
  end

  def verify_server_accept(client, msg) do
    # detached_signature_B = assert_nacl_secretbox_open(
    #   ciphertext: msg4,
    #   nonce: 24_bytes_of_zeros,
    #   key: sha256(
    #     concat(
    #       network_identifier,
    #       shared_secret_ab,
    #       shared_secret_aB,
    #       shared_secret_Ab
    #     )
    #   )
    # )

    {:ok, secretbox_key} = Salty.Hash.Sha256.hash client.network_identifier <> client.shared_secret_ab <> client.shared_secret_aB <> client.shared_secret_Ab
    {:ok, detached_signature_b} = Salty.Secretbox.primitive.open(
      msg,
      :binary.copy(<<0>>, 24),
      secretbox_key
    )

    # assert_nacl_sign_verify_detached(
    #   sig: detached_signature_B,
    #   msg: concat(
    #     network_identifier,
    #     detached_signature_A,
    #     client_longterm_pk,
    #     sha256(shared_secret_ab)
    #   ),
    #   key: server_longterm_pk
    # )

    {:ok, sha256_shared_secret_ab} = Salty.Hash.Sha256.hash client.shared_secret_ab
    :ok = Salty.Sign.primitive.verify_detached(
      detached_signature_b,
      client.network_identifier <> client.detached_signature_a <> client.identity.pub <> sha256_shared_secret_ab,
      client.other_pubkey
    )

    client = %{client | detached_signature_b: detached_signature_b}

    {:ok, client}
  end

  def boxstream_keys(state) do
    import Salty.Hash.Sha256, only: [hash: 1]

    {:ok, shared_secret} = shared_secret(state)
    {:ok, sha256_shared_secret} = hash(shared_secret)

    {:ok, encrypt_key} = hash(sha256_shared_secret <> state.other_pubkey)
    {:ok, decrypt_key} = hash(sha256_shared_secret <> state.identity.pub)

    encrypt_nonce = binary_part(state.other_ephemeral.pub, 0, 24)
    decrypt_nonce = binary_part(state.ephemeral.pub, 0, 24)

    %{
      shared_secret: shared_secret,
      encrypt_key: encrypt_key,
      decrypt_key: decrypt_key,
      encrypt_nonce: encrypt_nonce,
      decrypt_nonce: decrypt_nonce,
    }
  end
end


