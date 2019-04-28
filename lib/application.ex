defmodule Sailor.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Sailor.Discovery
    ]
    opts = [strategy: :one_for_one, name: Sailor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
