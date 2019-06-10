defmodule Sailor.MessageTest do
  use ExUnit.Case

  alias Sailor.Message
  alias Sailor.Keypair

  @msgs [
    {"simple msg", ~s({
      "previous": "%XphMUkWQtomKjXQvFGfsGYpt69sgEY7Y4Vou9cEuJho=.sha256",
      "author": "@FCX/tsDLpubCPKKfIrw4gc+SQkHcaD17s7GI6i/ziWY=.ed25519",
      "sequence": 2,
      "timestamp": 1514517078157,
      "hash": "sha256",
      "content": {
        "type": "post",
        "text": "Second post!"
      },
      "signature": "z7W1ERg9UYZjNfE72ZwEuJF79khG+eOHWFp6iF+KLuSrw8Lqa6IousK4cCn9T5qFa8E14GVek4cAMmMbjqDnAg==.sig.ed25519"
    })},

    {"msg with key, value", ~s({
      "key": "%XphMUkWQtomKjXQvFGfsGYpt69sgEY7Y4Vou9cEuJho=.sha256",
      "value": {
        "previous": null,
        "author": "@FCX/tsDLpubCPKKfIrw4gc+SQkHcaD17s7GI6i/ziWY=.ed25519",
        "sequence": 1,
        "timestamp": 1514517067954,
        "hash": "sha256",
        "content": {
          "type": "post",
          "text": "This is the first post!"
        },
        "signature": "QYOR/zU9dxE1aKBaxc3C0DJ4gRyZtlMfPLt+CGJcY73sv5abKKKxr1SqhOvnm8TY784VHE8kZHCD8RdzFl1tBA==.sig.ed25519"
      },
      "timestamp": 1514517067956
    })}
  ]


  test "Message.id" do
    {:ok, message} = Message.from_json(List.keyfind(@msgs, "simple msg", 0) |> elem(1))
    assert "%R7lJEkz27lNijPhYNDzYoPjM0Fp+bFWzwX0SmNJB/ZE=.sha256" = Message.id(message)
  end

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
      roundtrip = @msg
      |> Message.from_json()
      |> elem(1)
      |> Message.to_signing_string()

      assert @msg == roundtrip
    end

    test "Message.verify_signature for msg in #{msg_file}" do
      {:ok, message} = Message.from_json(@msg)
      assert :ok = Message.verify_signature(message)
    end
  end

  Enum.each @msgs, fn {name, msg} ->
    @msg msg

    test "Message.from_json for " <> name  do
      {:ok, _message} = Message.from_json(@msg)
    end

    test "Message.verify_signature for " <> name do
      {:ok, message} = Message.from_json(@msg)
      assert :ok = Message.verify_signature(message)
    end
  end
end
