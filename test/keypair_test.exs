defmodule Sailor.KeypairTest do
  use ExUnit.Case

  alias Sailor.Keypair

  test "Keypair.from_identifier(id)" do
    {:ok, keypair} = Keypair.from_identifier("@ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8=.ed25519")
    assert keypair.curve == :ed25519
    assert keypair.sec == nil
    assert keypair.pub == <<100, 162, 35, 27, 111, 61, 20, 29, 223, 100, 252, 138, 126, 210, 41, 60, 206, 113, 170, 4, 145, 4, 103, 113, 7, 146, 156, 98, 160, 236, 167, 31>>
  end

  test "Keypair.from_identifier(id) error" do
    :error = Keypair.from_identifier("ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8=.ed25519")
    :error = Keypair.from_identifier("@ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8.ed25519")
    :error = Keypair.from_identifier("@ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8=")
  end

  test "Keypair.{from_secret, to_secret}" do
    keypair = Keypair.random()
    {:ok, keypair2} = keypair |> Keypair.to_secret |> Keypair.from_secret
    assert keypair == keypair2
  end

  test "Keypair.load_secret(path)" do
    {:ok, keypair} = Keypair.load_secret "priv/secret.json"
    assert Keypair.id(keypair) == "@ZKIjG289FB3fZPyKftIpPM5xqgSRBGdxB5KcYqDspx8=.ed25519"
  end
end
