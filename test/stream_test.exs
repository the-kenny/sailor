defmodule Sailor.StreamTest do
  use ExUnit.Case

  alias Sailor.Stream
  alias Sailor.Stream.Message

  defp rand_id() do
    :base64.encode(:crypto.strong_rand_bytes(10))
  end

  test "Stream.for_peer with no messages has a sequence of 0" do
    stream = Stream.for_peer(rand_id())
    assert stream.sequence == 0
    assert Stream.empty?(stream)
  end

  test "Stream.append and Stream.persist!" do
    identity = rand_id()
    stream = Stream.for_peer(identity)
    assert Stream.empty?(stream)

    {:ok, stream} = Stream.append(stream, [%Message{id: rand_id(), author: identity, sequence: 1}])
    assert !Stream.empty?(stream)
    assert stream.sequence == 1
    assert length(stream.unsaved_messages) == 1

    {:ok, stream} = Stream.persist!(stream)
    assert stream.sequence == 1
    assert stream.unsaved_messages == []

    assert stream == Stream.for_peer(identity)
  end

end
