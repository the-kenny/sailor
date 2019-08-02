defmodule Sailor.MessageProcessing.Producer do
  use GenStage
  require Logger

  def start_link(opts) do
    GenStage.start_link(__MODULE__, nil, opts)
  end

  def init(nil) do
    {:producer, nil}
  end

  # TODO: Use `GenStage.call` as in https://hexdocs.pm/gen_stage/GenStage.html#module-buffering-demand to push new messages automatically

  def notify!() do
    GenStage.call(__MODULE__, :notify)
  end

  def unprocessed_message_count() do
    {:ok, [[count: count]]} = Sailor.Db.with_db(fn db ->
      Sqlitex.query(db, "SELECT count(id) as count from stream_messages where not processed")
    end)

    count
  end

  defp query_events(demand \\ -1) do
    {:ok, rows} = Sailor.Db.with_db(fn db ->
      Sqlitex.query(db, "SELECT id, json from stream_messages where not processed order by author, sequence limit ?", bind: [demand])
    end)

    events = Enum.map(rows, fn row -> {
        Keyword.get(row, :id),
        Keyword.get(row, :json)
      }
    end)

    {:ok, events}
  end

  def handle_demand(demand, state) when demand > 0 do
    Logger.info "Querying database for up to #{demand} unprocessed messages"

    {:ok, events} = query_events(demand)
    {:noreply, events, state}
  end

  def handle_call(:notify, _from, state) do
    {:ok, events} = query_events()
    {:reply, :ok, events, state} # Dispatch immediately
  end

end
