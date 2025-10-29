defmodule AITrace.Exporter.FileTest do
  use ExUnit.Case, async: true

  alias AITrace.{Exporter.File, Trace, Span, Event}

  @test_dir "/tmp/aitrace_file_test"

  setup do
    # Clean up test directory before each test
    :file.del_dir_r(String.to_charlist(@test_dir))
    :file.make_dir(String.to_charlist(@test_dir))

    on_exit(fn ->
      :file.del_dir_r(String.to_charlist(@test_dir))
    end)

    :ok
  end

  describe "init/1" do
    test "initializes with directory path" do
      opts = %{directory: @test_dir}
      assert {:ok, state} = File.init(opts)
      assert state.directory == @test_dir
    end

    test "creates directory if it doesn't exist" do
      dir = Path.join(@test_dir, "new_dir")
      refute :filelib.is_dir(String.to_charlist(dir))

      {:ok, _state} = File.init(%{directory: dir})

      assert :filelib.is_dir(String.to_charlist(dir))
    end

    test "defaults to ./traces directory" do
      {:ok, state} = File.init(%{})
      assert state.directory == "./traces"
    end
  end

  describe "export/2" do
    test "writes trace to JSON file" do
      {:ok, state} = File.init(%{directory: @test_dir})

      trace = Trace.new("test_trace_123")
      span = Span.new("operation") |> Span.finish()
      trace = Trace.add_span(trace, span)

      {:ok, _state} = File.export(trace, state)

      # Check that file was created
      {:ok, files} = :file.list_dir(String.to_charlist(@test_dir))
      assert length(files) == 1

      file_path = Path.join(@test_dir, to_string(hd(files)))
      {:ok, content} = :file.read_file(String.to_charlist(file_path))
      data = Jason.decode!(content)

      assert data["trace_id"] == "test_trace_123"
      assert is_list(data["spans"])
      assert length(data["spans"]) == 1
    end

    test "writes valid JSON with span details" do
      {:ok, state} = File.init(%{directory: @test_dir})

      trace = Trace.new("trace_123")

      span =
        Span.new("my_operation")
        |> Span.with_attributes(%{user_id: 42})
        |> Span.finish()

      trace = Trace.add_span(trace, span)

      {:ok, _state} = File.export(trace, state)

      {:ok, files} = :file.list_dir(String.to_charlist(@test_dir))
      file_path = Path.join(@test_dir, to_string(hd(files)))
      {:ok, content} = :file.read_file(String.to_charlist(file_path))
      data = Jason.decode!(content)

      span_data = hd(data["spans"])
      assert span_data["name"] == "my_operation"
      assert span_data["attributes"]["user_id"] == 42
      assert is_integer(span_data["start_time"])
      assert is_integer(span_data["end_time"])
    end

    test "includes events in JSON output" do
      {:ok, state} = File.init(%{directory: @test_dir})

      trace = Trace.new("trace_123")
      event = Event.new("cache_miss", %{key: "user_123"})

      span =
        Span.new("operation")
        |> Span.add_event(event)
        |> Span.finish()

      trace = Trace.add_span(trace, span)

      {:ok, _state} = File.export(trace, state)

      {:ok, files} = :file.list_dir(String.to_charlist(@test_dir))
      file_path = Path.join(@test_dir, to_string(hd(files)))
      {:ok, content} = :file.read_file(String.to_charlist(file_path))
      data = Jason.decode!(content)

      span_data = hd(data["spans"])
      assert is_list(span_data["events"])
      assert length(span_data["events"]) == 1

      event_data = hd(span_data["events"])
      assert event_data["name"] == "cache_miss"
      assert event_data["attributes"]["key"] == "user_123"
    end

    test "filename includes trace_id and timestamp" do
      {:ok, state} = File.init(%{directory: @test_dir})

      trace = Trace.new("my_trace")
      {:ok, _state} = File.export(trace, state)

      {:ok, files} = :file.list_dir(String.to_charlist(@test_dir))
      filename = to_string(hd(files))

      assert filename =~ "my_trace"
      assert filename =~ ".json"
    end
  end

  describe "shutdown/1" do
    test "returns :ok" do
      assert :ok = File.shutdown(%{directory: @test_dir})
    end
  end
end
