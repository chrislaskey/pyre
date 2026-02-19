defmodule PyreTest do
  use ExUnit.Case
  doctest Pyre

  test "greets the world" do
    assert Pyre.hello() == :world
  end
end
