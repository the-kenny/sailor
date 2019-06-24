defmodule Sailor.Rpc.HandlerRegistry do
  require Logger

  alias Sailor.Rpc.HandlerRegistry.HandlerServer

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link([]) do
    {:ok, registry} = Registry.start_link(keys: :unique, name: __MODULE__)

    handlers = [
      {Sailor.Rpc.HandlerRegistry.Blobs, ["/tmp/sailor_blobs"]},
      {Sailor.Rpc.HandlerRegistry.CreateHistoryStream, []}
    ]

    for {handler, args} <- handlers do
      register_handler(__MODULE__, handler, args)
    end

    {:ok, registry}
  end

  @spec register_handler(pid(), [any()]) :: :ok | {:error, String.t}
  @spec register_handler(term(), pid(), [any()]) :: :ok | {:error, String.t}
  def register_handler(registry \\ __MODULE__, handler, args) do
    child_spec = {
      HandlerServer,
      # [{self(), handler, args}, [name: {:via, Registry, {__MODULE__, handler, handler.function_names()}}]]
      [{registry, handler, args}, []]
    }

    {:ok, child} = DynamicSupervisor.start_child(Sailor.Rpc.HandlerSupervisor, child_spec)
    Logger.info "Started HandlerServer #{inspect child} for #{inspect handler.function_names()}"
    {:ok, child}
  end

  @spec dispatch(pid(), %Sailor.Rpc.Call{}) :: :ok, {:error, String.t}
  @spec dispatch(term(), pid(), %Sailor.Rpc.Call{}) :: :ok, {:error, String.t}
  def dispatch(registry \\ __MODULE__, peer, call) do
    case Registry.lookup(registry, call.name) do
      [{handler, _}] ->
        # Logger.debug "Dispatching #{inspect call.name} to #{inspect handler}"
        HandlerServer.dispatch(handler, peer, call)
      [] -> {:error, "No handler registered for #{inspect call.name}"}
    end
  end

  def dispatch_async(registry \\ __MODULE__, peer, call) do
    case Registry.lookup(registry, call.name) do
      [{handler, _}] ->
        # Logger.debug "Dispatching #{inspect call.name} async to #{inspect handler}"
        HandlerServer.dispatch_async(handler, peer, call)
      [] -> {:error, "No handler registered for #{inspect call.name}"}
    end
  end

  defmodule HandlerServer do
    use GenServer

    def start_link([{registry, handler, args}, opts]) do
      GenServer.start_link(__MODULE__, [{registry, handler, args}], opts)
    end

    def dispatch(server, peer, rpc_call) do
      GenServer.call(server, {:dispatch, peer, rpc_call})
    end

    def dispatch_async(server, peer, rpc_call) do
      GenServer.cast(server, {:dispatch, peer, rpc_call})
    end

    @impl GenServer
    def init([{registry, handler, args}]) do
      {:ok, handler_state} = handler.init(args)
      for fun <- handler.function_names() do
        Registry.register(registry, fun, handler)
      end
      {:ok, {registry, handler, handler_state}}
    end

    @impl GenServer
    def handle_call({:dispatch, peer, rpc_call}, _from, {registry, handler, handler_state}) do
      {:ok, new_state} = handler.handle_request(peer, rpc_call, handler_state)
      {:reply, :ok, {registry, handler, new_state}}
    end

    @impl GenServer
    def handle_cast({:dispatch, peer, rpc_call}, {registry, handler, handler_state}) do
      {:ok, new_state} = handler.handle_request(peer, rpc_call, handler_state)
      {:noreply, {registry, handler, new_state}}
    end
  end
end

defmodule Sailor.Rpc.Handler do
  @callback function_names() :: [[String.t]]
  @callback init(any()) :: {:ok, any()} | {:error, String.t}
  @callback handle_request(pid(), %Sailor.Rpc.Call{}, any()) :: {:ok, any()} | {:error, String.t}
  # TODO: Optional `handle_info` and `init`
end
