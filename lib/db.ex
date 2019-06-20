defmodule Sailor.Db do
  require Logger

  def child_spec([db_path]) do

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [db_path]}
    }
  end

  def start_link(db_path) do
    pool_config = [
      name: {:local, __MODULE__},
      worker_module: Sailor.Db.PoolWorker,
      size: 6,
      max_overflow: 2,
    ]
    worker_args = [db_path]
    :poolboy.start_link(pool_config, worker_args)
  end

  def with_db(fun) do
    :poolboy.transaction(__MODULE__, fn(worker) ->
      GenServer.call(worker, {:exec, fun})
    end)
  end
end
