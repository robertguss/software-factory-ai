defmodule Conveyor.CanonicalJsonTest do
  use ExUnit.Case, async: true

  alias Conveyor.CanonicalJson

  test "sorts object keys recursively and is independent of insertion order" do
    a = CanonicalJson.encode(%{"b" => 1, "a" => %{"y" => 2, "x" => 1}})
    b = CanonicalJson.encode(%{"a" => %{"x" => 1, "y" => 2}, "b" => 1})

    assert a == b
    assert a == ~s({"a":{"x":1,"y":2},"b":1})
  end

  test "encodes nil/booleans as JSON literals and other atoms as strings" do
    assert CanonicalJson.encode(nil) == "null"
    assert CanonicalJson.encode(true) == "true"
    assert CanonicalJson.encode(false) == "false"
    assert CanonicalJson.encode(:active) == ~s("active")

    # nil/true/false must not collide with their string spellings.
    refute CanonicalJson.encode(nil) == CanonicalJson.encode("nil")
    refute CanonicalJson.encode(true) == CanonicalJson.encode("true")
  end

  test "string and atom keys both sort by their string form" do
    assert CanonicalJson.encode(%{:a => 1, "b" => 2}) == ~s({"a":1,"b":2})
  end

  test "digest/1 is a stable, order-independent sha256 over the canonical encoding" do
    d1 = CanonicalJson.digest(%{"b" => 1, "a" => 2})
    d2 = CanonicalJson.digest(%{"a" => 2, "b" => 1})

    assert d1 == d2
    assert d1 =~ ~r/^sha256:[0-9a-f]{64}$/
  end
end
