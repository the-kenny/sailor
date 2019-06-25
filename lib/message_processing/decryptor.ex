defmodule Sailor.MessageProcessing.Decryptor do
  use GenStage
  require Logger
  alias Sailor.Stream.Message

  def start_link(opts) do
    GenStage.start_link(__MODULE__, nil, opts)
  end

  def init(nil) do
    {:producer_consumer, nil, subscribe_to: [Sailor.MessageProcessing.Producer]}
  end

  def handle_events(events, _from, state) do
    Logger.info "Decrypting #{length events} messages"
    messages = Enum.map(events, fn {db_id, json} ->
      {:ok, message} = Message.from_json(json)
      {db_id, maybe_decrypt_content(message)}
    end)

    {:noreply, messages, state}
  end

  defp maybe_decrypt_content(message) do
    if is_binary(Message.content(message)) do
      # Logger.warn "Unimplemented: decryption for message content of #{message.id}"
    end
    message
  end
end
