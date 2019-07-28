defmodule Sailor.Stream.MessageUtils do


  def fmap({k, v}), do: {k, fmap(v)}
  def fmap(x) when is_list(x), do: Enum.map(x, &fmap/1)

  def fmap(x) when is_float(x) do
    # digits = Sailor.Ecma262.g_fmt(x)
    # digits = if hd(digits) == ?. do
    #   '0' ++ digits
    # else
    #   digits
    # end
    digits = :mochinum.digits(x) |> to_string() |> String.replace_suffix(".0", "")
    {{:json, digits}}
  end

  def fmap(x) when is_map(x) do
    x |> Map.to_list() |> Enum.map(&fmap/1) |> Enum.into(%{})
  end

  def fmap(x), do: x
end
