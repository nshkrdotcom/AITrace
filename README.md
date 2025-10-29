# AITrace

> The unified observability layer for the AI Control Plane.

`AITrace` provides the unified observability layer for the AI Control Plane, transforming opaque, non-deterministic AI processes into fully interpretable and debuggable execution traces.

Its mission is to create an Elixir-native instrumentation library and a corresponding data model that captures the complete causal chain of an AI agent's reasoning process—from initial prompt to final output, including all thoughts, tool calls, and state changes—enabling a true "Execution Cinema" experience for developers and operators.

## The Problem: Why Traditional Observability Fails

Debugging a simple web request is a solved problem. We have structured logs, metrics, and distributed tracing (like OpenTelemetry) that show the path of a request through a series of stateless services.

Debugging an AI agent is fundamentally different. It is like performing forensic analysis on a dream. The challenges are unique:

*   **Non-Determinism:** The same input can produce different outputs and, more importantly, different *reasoning paths*.
*   **Deeply Nested Causality:** A final answer may be the result of a multi-step chain of thought, where an LLM hallucinates, calls the wrong tool with the wrong arguments, misinterprets the result, and then tries to correct itself.
*   **Stateful Complexity:** Agents are not stateless. Their behavior is conditioned by memory, scratchpads, and the history of the conversation. A simple log line is insufficient to capture the state that led to a decision.
*   **Polyglot Execution:** An agent's "thought" may happen in Elixir, but its "action" (e.g., running a code interpreter) happens in a sandboxed Python environment. Tracing this flow across language boundaries is notoriously difficult.

`Logger.info/1` is inadequate. Traditional APM tools provide a high-level view but lack the granular, AI-specific context needed to answer the most important question: **"Why did the agent do *that*?"**

## Core Concepts & Data Model

`AITrace` is built on a few simple but powerful concepts, heavily inspired by OpenTelemetry but adapted for AI workflows.

*   **Trace:** The complete, end-to-end record of a single transaction (e.g., one user message to an agent). It is identified by a unique `trace_id`. A trace is composed of a root `Span` and many nested `Spans` and `Events`.

*   **Span:** A record of a timed operation with a distinct start and end. A span represents a unit of work. Examples: `llm_call`, `tool_execution`, `prompt_rendering`. Spans can be nested to represent a call graph. Each span has a `name`, `start_time`, `end_time`, and a key-value map of `attributes`.

*   **Event:** A point-in-time annotation within a `Span`. It represents a notable occurrence that isn't a timed operation. Examples: `agent_state_updated`, `validation_failed`, `tool_not_found`.

*   **Context:** An immutable Elixir map (`%AITrace.Context{}`) that carries the `trace_id` and the current `span_id`. This context is explicitly passed through the entire call stack of a traced operation, ensuring all telemetry is correctly correlated.

## Installation

Add `aitrace` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:aitrace, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
defmodule MyApp.Agent do
  require AITrace  # Required to use the macros

  def handle_user_message(message, state) do
    # 1. Start a new trace for the entire transaction
    AITrace.trace "agent.handle_message" do
      # 2. Add point-in-time events with rich metadata
      AITrace.add_event("request_received", %{message_length: String.length(message)})

      # 3. Wrap discrete, timed operations in spans
      response = AITrace.span "reasoning_loop" do
        # Add attributes to the current span
        AITrace.with_attributes(%{model: "gpt-4", temperature: 0.7})

        # Perform reasoning
        think_about(message)
      end

      AITrace.add_event("reasoning_complete", %{token_usage: response.tokens})

      {:reply, response.answer, update_state(state)}
    end
  end
end
```

## Core API

### Starting a Trace

```elixir
AITrace.trace "operation_name" do
  # Your code here - context is stored in process dictionary
end
```

### Creating Spans

```elixir
AITrace.span "span_name" do
  # Timed operation - duration is automatically measured
end
```

### Adding Events

```elixir
AITrace.add_event("event_name", %{key: "value"})
AITrace.add_event("simple_event")  # No attributes
```

### Adding Attributes

```elixir
AITrace.with_attributes(%{user_id: 42, region: "us-west"})
```

### Accessing Context

```elixir
ctx = AITrace.get_current_context()
IO.inspect(ctx.trace_id)
IO.inspect(ctx.span_id)
```

## Configuration

Configure exporters in your application config:

```elixir
# config/config.exs
config :aitrace,
  exporters: [
    {AITrace.Exporter.Console, verbose: true, color: true},
    {AITrace.Exporter.File, directory: "./traces"}
  ]
```

### Available Exporters

*   **`AITrace.Exporter.Console`** - Prints human-readable traces to stdout
  - Options: `verbose` (show attributes/events), `color` (ANSI colors)

*   **`AITrace.Exporter.File`** - Writes JSON traces to files
  - Options: `directory` (output directory, default: "./traces")

### Creating Custom Exporters

Implement the `AITrace.Exporter` behavior:

```elixir
defmodule MyApp.CustomExporter do
  @behaviour AITrace.Exporter

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def export(trace, state) do
    # Send trace to your backend
    IO.inspect(trace)
    {:ok, state}
  end

  @impl true
  def shutdown(_state), do: :ok
end
```

## Examples

See `examples/basic_usage.exs` for a complete working example:

```bash
mix run examples/basic_usage.exs
```

Output:
```
Trace: b37b73325dbd626481e0ff3e89de02c8
▸ reasoning (10.84ms) ✓
  Attributes: %{model: "gpt-4", temperature: 0.7}
    • reasoning_complete
      %{thought_count: 3}
▸ tool_execution (5.95ms) ✓
  Attributes: %{tool: "web_search"}
▸ response_generation (8.98ms) ✓
  Attributes: %{tokens: 150}
```

## Architecture

### Data Model

- **AITrace.Context** - Carries trace_id and span_id through the call stack
- **AITrace.Span** - Timed operations with start/end times, attributes, and events
- **AITrace.Event** - Point-in-time annotations within spans
- **AITrace.Trace** - Complete trace containing all spans

### Runtime

- **AITrace.Collector** - In-memory Agent storing active traces
- **AITrace.Application** - Supervision tree managing the collector
- Context stored in process dictionary for implicit propagation

### Future Integrations

`AITrace` is designed to integrate with other AI infrastructure:

*   **DSPex** - Automatic instrumentation for LLM calls and prompt rendering
*   **Altar** - Tool execution tracing with arguments and results
*   **Snakepit** - Cross-language tracing via gRPC metadata
*   **Phoenix Channels** - Real-time trace streaming to web UIs
*   **OpenTelemetry** - Export to standard observability platforms

## Development Status

**✅ Implemented (v0.1.0)**
- Core data structures (Context, Span, Event, Trace)
- Trace and span macros with automatic timing
- Event and attribute APIs
- Console exporter (human-readable output)
- File exporter (JSON format)
- Comprehensive test suite (80 tests)
- Working examples

**🚧 Planned**
- Phoenix Channel exporter for real-time streaming
- OpenTelemetry exporter
- OTP integration helpers (GenServer, Oban)
- Cross-process context propagation
- "Execution Cinema" web UI with waterfall views
- DSPex, Altar, and Snakepit integrations

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run example
mix run examples/basic_usage.exs
```

## License

MIT - See [LICENSE](LICENSE) for details.

## Contributing

AITrace is part of the AI Control Plane ecosystem. Contributions welcome!