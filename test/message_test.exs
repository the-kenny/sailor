defmodule Sailor.Stream.MessageTest do
  use ExUnit.Case, async: true

  alias Sailor.Stream.Message

  @msgs File.read!("priv/tests/messages")
    |> String.split("\n\n")
    |> Stream.filter(&String.starts_with?(&1, "%"))
    |> Stream.map(&String.split(&1, "\n", parts: 2))
    |> Stream.map(fn [k, v] -> {k, v} end)

  Enum.each @msgs, fn {message_id, message_json} ->
    @message_id message_id
    @message_json message_json

    test "Message.to_compact_json roundtrip for msg #{message_id}" do
      assert {:ok, message} = Message.from_json(@message_json)
      json = Message.to_compact_json(message)
      assert {:ok, roundtrip_message} = Message.from_json(json)

      assert message == roundtrip_message
    end

    test "Message.verify_signature for msg #{message_id}" do
      {:ok, message} = Message.from_json(@message_json)
      assert :ok == Message.verify_signature(message)
    end

    test "Message.id generates correct id for msg #{message_id}" do
      {:ok, message} = Message.from_json_unchecked(@message_json)
      assert @message_id == Message.calculate_id(message)
    end
  end

  @create_history_stream_msgs File.read!("priv/tests/history_stream.json")
  |> String.split("\n\n")

  Enum.each Stream.with_index(@create_history_stream_msgs), fn {message_json, index} ->
    @message_json message_json

    test "Message.to_compact_json roundtrip for msg at index #{index}" do
      assert {:ok, message} = Message.from_history_stream_json(@message_json)
      json = Message.to_compact_json(message)
      assert {:ok, roundtrip_message} = Message.from_json(json)

      assert message == roundtrip_message
    end

    test "Message.verify_signature for msg at index #{index}" do
      assert {:ok, message} = Message.from_history_stream_json(@message_json)
      assert :ok == Message.verify_signature(message)
    end
  end
end
