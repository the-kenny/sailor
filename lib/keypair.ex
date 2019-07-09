defmodule Sailor.Keypair do
  defstruct [:curve, :pub, :sec]

  def from_identifier(id) do
    with <<"@", pub_base64 :: bytes-size(44), ".", curve :: binary>> <- id,
         {:ok, pub} <- Base.decode64(pub_base64)
    do
      keypair = %__MODULE__{
        curve: String.to_existing_atom(curve),
        pub: pub,
      }

      {:ok, keypair}
    else
      _ -> {:error, :invalid}
    end
  end

  def from_pubkey(pubkey) do
    %__MODULE__{
      curve: :ed25519,
      pub: pubkey
    }
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
      id: identifier(keypair)
    }
  end

  def identifier(keypair) do
    if keypair.curve == nil do
      raise "Can't create identifier without `curve`"
    end
    "@" <> Base.encode64(keypair.pub) <> "." <> to_string keypair.curve
  end

  def random() do
    {:ok, pub, sec} = Salty.Sign.Ed25519.keypair()
    true = Salty.Sign.Ed25519.publickeybytes == byte_size(pub)
    true = Salty.Sign.Ed25519.secretkeybytes == byte_size(sec)
    %__MODULE__{curve: :ed25519, pub: pub, sec: sec}
  end

  def random_curve_25519() do
    {:ok, pub, sec} = Salty.Box.primitive.keypair()
    true = Salty.Box.primitive.publickeybytes == byte_size(pub)
    true = Salty.Box.primitive.secretkeybytes == byte_size(sec)
    %__MODULE__{curve: :curve25519, pub: pub, sec: sec}
  end
end
