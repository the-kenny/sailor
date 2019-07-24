defmodule Sailor.MessageProcessing.Decryptor do
  use GenStage
  require Logger
  alias Sailor.Stream.Message

  def start_link(opts) do
    GenStage.start_link(__MODULE__, nil, opts)
  end

  def init(nil) do
    {:producer_consumer, nil, subscribe_to: [{Sailor.MessageProcessing.Producer, max_demand: 1}]}
  end

  def handle_events(events, _from, state) do
    Logger.info "Decrypting #{length events} messages"
    messages = Enum.flat_map(events, fn {db_id, json} ->
      Logger.info "Decrypting #{db_id} #{json}"
      {:ok, message} = Message.from_json(json)
      case maybe_decrypt_content(message) do
        [] ->
          Logger.warn "Unimplemented: decryption for message content of #{message.id}"
          Sailor.Db.with_db(fn db -> Message.mark_processed!(db, db_id) end)
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
