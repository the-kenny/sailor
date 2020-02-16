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
    Logger.debug "Decrypting #{length events} messages"

    messages = Enum.flat_map(events, fn {db_id, json} ->
      {:ok, message} = Message.from_json(json)

      case maybe_decrypt_content(message) do
        [] ->
          # Hack: Skip message to prevent infinite loop
          Message.mark_processed!(Sailor.Db, db_id)
          []
        [msg] ->
          [{db_id, msg}]
      end
    end)

    {:noreply, messages, state}
  end

  defp maybe_decrypt_content(message) do
    if is_binary(message.content) do
      []
    else
      [message]
    end
  end
end
