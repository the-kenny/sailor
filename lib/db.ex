defmodule Sailor.Db do
  require Logger

  def child_spec([db_path]) do

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [db_path]}
    }
  end

  # TODO: Add a `Registry` to make announcement about table updates

  def start_link(db_path) do
    Sqlitex.with_db(db_path, fn db ->
      if !initialized?(db) do
        Logger.info "Initializing database #{inspect db_path}"
        :ok = initialize!(db)
      end
    end)

    :wpool.start_pool(__MODULE__, [
      workers: 20,
      worker: {Sailor.Db.PoolWorker, [db_path]},
      overrun_warning: 1_000,
    ])
  end

  def with_db(fun) do
    time = Time.utc_now

    res = :wpool.call(__MODULE__, {:exec, fun})

    diff_ms = Time.diff(Time.utc_now, time, :microsecond)/1000
    # acquiration_diff_ms = Time.diff(Time.utc_now, acquiration_time, :microsecond)/1000
    if diff_ms > 50 do
      Logger.warn "with_db took #{inspect diff_ms}ms, fn: #{inspect fun}"
    end

    res
  end

  @doc """
    Runs `fun` inside a transaction. If `fun` returns without raising an exception,
    the transaction will be commited via `commit`. Otherwise, `rollback` will be called.
    ## Examples
      iex> {:ok, db} = Sqlitex.open(":memory:")
      iex> Sqlitex.with_transaction(db, fn(db) ->
      ...>   Sqlitex.exec(db, "create table foo(id integer)")
      ...>   Sqlitex.exec(db, "insert into foo (id) values(42)")
      ...> end)
      iex> Sqlitex.query(db, "select * from foo")
      {:ok, [[{:id, 42}]]}
  """
  @spec with_transaction(Sqlitex.connection, (Sqlitex.connection -> any()), Keyword.t) :: any
  def with_transaction(db, fun, opts \\ []) do
    with :ok <- Sqlitex.exec(db, "begin immediate", opts),
      {:ok, result} <- apply_rescuing(fun, [db]),
      :ok <- Sqlitex.exec(db, "commit", opts)
    do
      {:ok, result}
    else
      err ->
        :ok = Sqlitex.exec(db, "rollback", opts)
        err
    end
  end


  def initialized?(db) do
    case Sqlitex.query(db, "select true from sqlite_master where type = 'table' and name = ?", bind: ["stream_messages"]) do
      {:ok, []} -> false
      {:ok, [_]} -> true
    end
  end

  def initialize!(db) do
    schema_file = Path.join([Application.app_dir(:sailor), "priv", "schema.sql"])

    :ok = Sqlitex.exec(db, File.read!(schema_file))
    :ok = Sqlitex.exec(db, "vacuum")
  end

  defp apply_rescuing(fun, args) do
    try do
      {:ok, apply(fun, args)}
    rescue
      error -> {:error, error}
    end
  end
end

defmodule Sailor.Db.PoolWorker do
  use GenServer

  require Logger

  def start_link([db_path]) do
    GenServer.start_link(__MODULE__, [db_path])
  end

  def init([db_path]) do
    {:ok, db} = Sqlitex.open(db_path)
    :ok = Sqlitex.exec(db, "PRAGMA journal_mode=WAL")
    :ok = Sqlitex.exec(db, "PRAGMA foreign_keys = ON")
    # :ok = Sqlitex.exec(db, "PRAGMA busy_timeout = 2000")
    {:ok, db}
  end

  def handle_call({:exec, fun}, _from, db) do
    result = apply(fun, [db])
    {:reply, result, db}
  end

  def terminate(_, db) do
    Sqlitex.close(db)
  end
end
