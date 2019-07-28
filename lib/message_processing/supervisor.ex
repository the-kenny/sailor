defmodule Sailor.MessageProcessing.Supervisor do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, :init, [])
  end

  def init(_) do
    if Mix.env == :test do
      :ignore
    else
      children = [
        {Sailor.MessageProcessing.Producer, name: Sailor.MessageProcessing.Producer},
        {Sailor.MessageProcessing.Decryptor, name: Sailor.MessageProcessing.Decryptor},
        {Sailor.MessageProcessing.Consumer, name: Sailor.MessageProcessing.Consumer},
      ]
      Supervisor.init(children, strategy: :rest_for_one)
    end
  end
end
