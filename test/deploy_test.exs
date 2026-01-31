defmodule DeployTest do
  use ExUnit.Case
  doctest Deploy

  test "greets the world" do
    assert Deploy.hello() == :world
  end
end
