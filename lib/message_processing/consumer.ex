defmodule Sailor.MessageProcessing.Consumer do
  use GenStage
  require Logger

  alias Sailor.Stream.Message

  @max_batch_size 50

   def start_link(opts) do
    GenStage.start_link(__MODULE__, nil, opts)
  end

  def init(nil) do
    {:consumer, nil, subscribe_to: [{Sailor.MessageProcessing.Decryptor, max_demand: @max_batch_size}]}
  end

  def handle_events(events, _from, state) do

    Sailor.Db.with_db(fn db ->
      for {db_id, message} <- events do
         message_content = Message.content(message) |> Enum.into(%{})
        %{"type" => message_type} = message_content
        module = Module.concat(Sailor.MessageProcessing.Handlers, String.capitalize(message_type))

        # TODO: `Code.ensure_loaded` is slow. Use an explicit map (in config.exs)
        case Code.ensure_loaded(module) do
          {:module, handler} -> handler.handle!(db, db_id, message)
          {:error, _err} -> nil #Logger.warn "Found no handler for message type #{inspect message_type}. Is #{inspect module} loaded?"
        end

        # handler.handle!(db, db_id, message_content)

        # for blob <- Sailor.Utils.message_blobs(message) do
        #   if !Sailor.Blob.available?(blob) do
        #     :ok = Sailor.Blob.mark_wanted!(blob)
        #   end
        # end

        Message.mark_processed!(db, db_id)
      end

      Logger.info("Marked #{length events} messages as processed")
    end)

    # We are a consumer, so we would never emit items.
    {:noreply, [], state}
  end

end
