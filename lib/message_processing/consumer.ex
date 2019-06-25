defmodule Sailor.MessageProcessing.Consumer do
  use GenStage
  require Logger

  alias Sailor.Stream.Message

  def start_link(opts) do
    GenStage.start_link(__MODULE__, nil, opts)
  end

  def init(nil) do
    {:consumer, nil, subscribe_to: [Sailor.MessageProcessing.Decryptor]}
  end

  def handle_events(events, _from, state) do
    Logger.info("Marking #{length events} messages as processed")

    Sailor.Db.with_db(fn db ->
      for {db_id, message} <- events do
        for blob <- Sailor.Utils.message_blobs(message) do
          if !Sailor.Blob.available?(blob) do
            :ok = Sailor.Blob.mark_wanted!(blob)
          end
        end

        {:ok, _} = Sqlitex.query(db, "update stream_messages set processed = true where id = ?", bind: [db_id])
      end
    end)

    # We are a consumer, so we would never emit items.
    {:noreply, [], state}
  end

end
