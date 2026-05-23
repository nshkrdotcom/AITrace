defmodule AITrace.HashTest do
  use ExUnit.Case, async: true

  test "normalizes atom and string map keys deterministically" do
    assert AITrace.Hash.term(%{b: 1, a: 2}) == AITrace.Hash.term(%{"a" => 2, "b" => 1})
  end

  test "hashes transcript role and content only" do
    messages = [
      %{role: "system", content: "role prompt", ignored: true},
      %{"role" => "user", "content" => "hello"}
    ]

    assert AITrace.Hash.messages(messages) ==
             AITrace.Hash.term([
               %{role: "system", content: "role prompt"},
               %{role: "user", content: "hello"}
             ])
  end
end
