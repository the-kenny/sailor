defmodule Sailor.Rpc.Handler do
  @type rpc_request   :: {:rpc_request, rpc_function, rpc_type, rpc_args, pid()}
  @type rpc_function :: [String.t()]
  @type rpc_type      :: String.t()
  @type rpc_args      :: [map()]

  def call(handler, rpc_function, rpc_type, rpc_args, sender) do
    Process.send(handler, {:rpc_request, rpc_function, rpc_type, rpc_args, sender}, [])
  end
end
