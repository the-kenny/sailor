defmodule Sailor.MessageProcessing.Producer do
  use GenStage
  require Logger

  @max_batch_size 1000

  def start_link(opts) do
    GenStage.start_link(__MODULE__, nil, opts)
  end

  def init(nil) do
    {:producer, {:demand, 0}}
  end

  # TODO: Use `GenStage.call` as in https://hexdocs.pm/gen_stage/GenStage.html#module-buffering-demand to push new messages automatically

  def notify!() do
    GenStage.call(__MODULE__, :notify)
  end

  defp query_events(demand \\ -1) do
    {:ok, result} = Exqlite.query(Sailor.Db, "SELECT id, json from stream_messages where not processed order by author, sequence limit ?", [
      min(@max_batch_size, demand)
    ])

    events = Enum.map(result.rows, fn row ->
      {
        Keyword.get(row, :id),
        Keyword.get(row, :json)
      }
    end)

    {:ok, events}
  end

  @spec handle_demand(any, any) :: {:noreply, [any], any}
  def handle_demand(demand, {:demand, n}) when demand > 0 do
    Logger.info "Querying database for up to #{demand} unprocessed messages"

    demand = demand + n

    {:ok, events} = query_events(demand)

    pending_demand = demand - length(events)

    {:noreply, events, {:demand, pending_demand}}
  end

  def handle_call(:notify, _from, {:demand, n}) do
    {:ok, events} = query_events(n)
    pending_demand = n - length(events)
    {:reply, :ok, events, {:demand, pending_demand}}
  end

end
