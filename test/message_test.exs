defmodule Sailor.Stream.MessageTest do
  use ExUnit.Case

  alias Sailor.Stream.Message
  alias Sailor.Keypair

  @legacy_message ~s({"previous":"%5vRiWqlTOUsY6MM1I/lcQqCkw1F09BSmI6BnPD7FWcc=.sha256","sequence":32,"author":"@mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=.ed25519","timestamp":1557303668620,"hash":"sha256","content":{"type":"contact","contact":"@EvIllh9vj5gYABPBjNPWvkABcVp0rUbp4EoA0tXPhFY=.ed25519","following":true},"signature":"QMtIicJmiaEGxFAgyB8Hg9FABJdcPjaHlXubN5J+GrElGoVHxfU5SLle6HCSreSAutJ8CNwSVmvLbGsheGRkDA==.sig.ed25519"})

  test "Message.verify_signature for legacy formats" do
    {:ok, message} = Message.from_json(@legacy_message)
    assert :ok = Message.verify_signature(message)
  end

  test "Message.id for legacy formats" do
    {:ok, message} = Message.from_json(@legacy_message)
    # assert nil = Message.id(message)
    assert "%lp3Ev8vnaL9X9IpSjV4FmqD/pBRknyBSIFVbfyxjP9o=.sha256" = Message.legacy_id(message)
  end

  @msg_files File.ls!("priv/tests/") |> Enum.map(&Path.join("priv/tests/", &1))

  Enum.each @msg_files, fn msg_file ->
    @msg File.read!(msg_file)

    test "Message roundtrip for msg in #{msg_file}" do
      {:ok, message} = Message.from_json(@msg)
      assert @msg == Message.to_signing_string(message.data)
    end

    test "Message.verify_signature for msg in #{msg_file}" do
      {:ok, message} = Message.from_json(@msg)
      assert :ok = Message.verify_signature(message)
    end
  end
end
