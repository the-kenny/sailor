defmodule Sailor.Rpc.HandlerRegistry do
  require Logger

  def child_spec([]) do
    %{
      id: __MODULE__,
      start: {Registry, :start_link, [[keys: :unique, name: __MODULE__]]}
    }
  end

  def register_handler(function_name, handler_pid) do
    register_handler(__MODULE__, function_name, handler_pid)
  end

  def register_handler(_registry, function_name, _handler) when not is_list(function_name) do
    {:error, "function_name is not a list"}
  end

  def register_handler(_registry, _function_name, handler_pid) when not is_pid(handler_pid) do
    {:error, "Handler must be a PID"}
  end

  def register_handler(registry, function_name, handler_pid) do
    Logger.info "Registering #{inspect handler_pid} as RPC handler for #{inspect function_name}"
    Registry.register(registry, function_name, handler_pid)
  end
end
