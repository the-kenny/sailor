defmodule Sailor.MessageTest do
  use ExUnit.Case

  alias Sailor.Message
  alias Sailor.Keypair

  @msg ~s({
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
  })

  @msg2 ~s({
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
    })

  test "Message.message_id" do
    {:ok, message} = Message.from_json(@msg)
    assert {:ok, "%R7lJEkz27lNijPhYNDzYoPjM0Fp+bFWzwX0SmNJB/ZE=.sha256"} = Message.message_id(message)
  end

  test "Message.verify_signature" do
    {:ok, message} = Message.from_json(@msg)
    {:ok, author_identity} = Keypair.from_identifier(message.author)
    assert :ok = Message.verify_signature(message, author_identity)
  end

  test "Message.verify_signature on msg2" do
    {:ok, message} = Message.from_json(@msg2)
    {:ok, author_identity} = Keypair.from_identifier(message.author)
    assert :ok = Message.verify_signature(message, author_identity)
  end
end
