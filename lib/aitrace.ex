defmodule AITrace do
  @moduledoc """
  The unified observability layer for the AI Control Plane.

  AITrace provides instrumentation for capturing the complete causal chain
  of an AI agent's reasoning process.

  ## Quick Start

      defmodule MyAgent do
        require AITrace

        def handle_message(message) do
          AITrace.trace "agent.handle_message" do
            AITrace.add_event("Message received", %{text: message})

            AITrace.span "reasoning_loop" do
              # Perform reasoning
              result = think_about(message)

              AITrace.with_attributes(%{tokens: result.token_count})
              result
            end
          end
        end
      end

  ## Core Concepts

  - **Trace**: The complete record of a transaction, identified by a `trace_id`
  - **Span**: A timed operation within a trace (can be nested)
  - **Event**: A point-in-time annotation within a span
  - **Context**: An immutable map carrying trace and span IDs through the call stack

  ## Exporters

  Configure exporters in your config:

      config :aitrace,
        exporters: [
          {AITrace.Exporter.Console, verbose: true},
          {AITrace.Exporter.File, directory: "./traces"}
        ]
  """

  alias AITrace.{Context, Collector, Span, Event}

  @doc """
  Starts a new trace.

  The `trace` macro creates a new trace and stores the context in the
  process dictionary. Use `AITrace.get_current_context()` to retrieve it.

  ## Examples

      require AITrace

      AITrace.trace "user_request" do
        process_request()
      end

  Returns the result of the block.
  """
  defmacro trace(name, do: block) do
    quote do
      ctx = AITrace.start_trace(unquote(name))
      AITrace.set_current_context(ctx)

      try do
        result = unquote(block)
        AITrace.finish_trace(ctx)
        result
      rescue
        error ->
          AITrace.finish_trace(ctx, :error)
          reraise error, __STACKTRACE__
      end
    end
  end

  @doc """
  Creates a span within a trace.

  The `span` macro creates a timed operation within the current trace.
  Use `AITrace.get_current_context()` to access the current context.

  ## Examples

      AITrace.trace "request" do
        AITrace.span "database_query" do
          query_database()
        end
      end

  Returns the result of the block.
  """
  defmacro span(name, do: block) do
    quote do
      parent_ctx = AITrace.get_current_context()
      ctx = AITrace.start_span(parent_ctx, unquote(name))
      AITrace.set_current_context(ctx)

      try do
        result = unquote(block)
        AITrace.finish_span(ctx)
        # Restore parent context
        AITrace.set_current_context(parent_ctx)
        result
      rescue
        error ->
          AITrace.finish_span(ctx, :error)
          AITrace.set_current_context(parent_ctx)
          reraise error, __STACKTRACE__
      end
    end
  end

  @doc """
  Adds an event to the current span.

  ## Examples

      AITrace.add_event("cache_hit", %{key: "user_123"})
      AITrace.add_event("validation_passed")
  """
  @spec add_event(String.t(), map()) :: :ok
  def add_event(name, attributes \\ %{}) do
    ctx = get_current_context()

    if ctx && ctx.span_id do
      event = Event.new(name, attributes)

      Collector.update_span(ctx.trace_id, ctx.span_id, fn span ->
        Span.add_event(span, event)
      end)
    end

    :ok
  end

  @doc """
  Adds attributes to the current span.

  ## Examples

      AITrace.with_attributes(%{user_id: 42, region: "us-west"})
  """
  @spec with_attributes(map()) :: :ok
  def with_attributes(attributes) when is_map(attributes) do
    ctx = get_current_context()

    if ctx && ctx.span_id do
      Collector.update_span(ctx.trace_id, ctx.span_id, fn span ->
        Span.with_attributes(span, attributes)
      end)
    end

    :ok
  end

  @doc """
  Gets the current context from the process dictionary.
  """
  @spec get_current_context() :: Context.t() | nil
  def get_current_context do
    Process.get(:aitrace_context)
  end

  @doc """
  Sets the current context in the process dictionary.
  """
  @spec set_current_context(Context.t()) :: :ok
  def set_current_context(%Context{} = ctx) do
    Process.put(:aitrace_context, ctx)
    :ok
  end

  # Private API functions

  @doc false
  def start_trace(name) do
    ctx = Context.new()
    Collector.new_trace(ctx.trace_id)
    Context.with_metadata(ctx, %{name: name})
  end

  @doc false
  def finish_trace(%Context{} = ctx, _status \\ :ok) do
    trace = Collector.get_trace(ctx.trace_id)

    if trace do
      # Export to configured exporters
      export_trace(trace)
      Collector.remove_trace(ctx.trace_id)
    end

    :ok
  end

  @doc false
  def start_span(%Context{} = ctx, name) do
    parent_span_id = ctx.span_id

    span =
      if parent_span_id do
        Span.new(name, parent_span_id)
      else
        Span.new(name)
      end

    Collector.add_span(ctx.trace_id, span)
    Context.with_span_id(ctx, span.span_id)
  end

  @doc false
  def finish_span(%Context{} = ctx, status \\ :ok) do
    if ctx.span_id do
      Collector.update_span(ctx.trace_id, ctx.span_id, fn span ->
        span
        |> Span.finish()
        |> Span.with_status(status)
      end)
    end

    :ok
  end

  # Export trace to configured exporters
  defp export_trace(trace) do
    exporters = Application.get_env(:aitrace, :exporters, [])

    Enum.each(exporters, fn
      {exporter_module, opts} ->
        {:ok, state} = exporter_module.init(opts)
        exporter_module.export(trace, state)

      exporter_module when is_atom(exporter_module) ->
        {:ok, state} = exporter_module.init(%{})
        exporter_module.export(trace, state)
    end)
  end
end
