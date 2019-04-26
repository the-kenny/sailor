defmodule SailorTest do
  use ExUnit.Case
  doctest Sailor

  test "greets the world" do
    assert Sailor.hello() == :world
  end
end
