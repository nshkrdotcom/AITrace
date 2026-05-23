defmodule AITrace.JSONLTest do
  use ExUnit.Case, async: true

  test "appends one normalized JSON line" do
    path =
      Path.join(System.tmp_dir!(), "aitrace-jsonl-#{System.unique_integer([:positive])}.jsonl")

    on_exit(fn -> File.rm(path) end)

    assert :ok = AITrace.JSONL.append(path, %{event: :route_selected, tuple: {:a, 1}})
    assert {:ok, contents} = File.read(path)
    assert {:ok, decoded} = contents |> String.trim() |> Jason.decode()

    assert decoded["event"] == "route_selected"
    assert decoded["tuple"] == ["a", 1]
  end
end
