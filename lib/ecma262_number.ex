defmodule Sailor.Ecma262 do

@on_load :load_nifs

  def load_nifs do
    :erlang.load_nif('./ecma262', 0)
  end

  def g_fmt(_f) do
    raise "NIF g_fmt not implemented"
  end
end
