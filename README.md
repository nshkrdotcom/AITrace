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

## Architectural Design & API

`AITrace` is designed as a set of ergonomic Elixir macros and functions that make instrumentation feel natural.

### The Core API

```elixir
# lib/my_app/agent.ex

def handle_user_message(message, state) do
  # 1. Start a new trace for the entire transaction
  AITrace.trace "agent.handle_message" do
    # The `trace` macro injects a `ctx` variable into the scope.
    
    # 2. Add point-in-time events with rich metadata.
    AITrace.add_event(ctx, "Initial state loaded", %{agent_id: state.id})

    # 3. Wrap discrete, timed operations in spans.
    {:ok, response, new_ctx} = AITrace.span ctx, "reasoning_loop" do
      # The `span` macro also yields a new, updated context.
      DSPex.execute(reasoning_logic, %{message: message}, context: new_ctx)
    end
    
    # new_ctx now contains the updated span information.
    AITrace.add_event(new_ctx, "Reasoning complete", %{token_usage: response.token_usage})
    
    {:reply, response.answer, update_state(state)}
  end
end
```

### Key Design Points

*   **Context Propagation:** The biggest challenge is passing the `ctx`. The API will provide helpers and patterns (like using a `with` block) to make this propagation clear and explicit, avoiding "magic" context passing.
*   **OTP Integration:** The library will include helpers for stashing and retrieving the `AITrace` context in `GenServer` calls and `Oban` jobs, making it easy to continue a trace across process boundaries.
*   **Pluggable Backends (Exporters):** `AITrace` itself is only responsible for generating telemetry data. It will use a configurable "Exporter" to send this data somewhere. This makes the system incredibly flexible.
    *   `AITrace.Exporter.Console`: Prints human-readable traces to the terminal for local development.
    *   `AITrace.Exporter.File`: Dumps structured JSON traces to a file.
    *   `AITrace.Exporter.Phoenix`: (Future) A backend that sends traces over Phoenix Channels to a live UI.
    *   `AITrace.Exporter.OpenTelemetry`: (Future) A backend that converts `AITrace` data into OTel format for integration with existing systems like Jaeger or Honeycomb.

## Integration with the Ecosystem

`AITrace` is the glue that binds the entire portfolio into a single, observable system.

*   **`DSPex` Instrumentation:** `DSPex` will be modified to accept an optional `AITrace.Context`. When provided, it will automatically create spans for `llm_call`, `prompt_render`, and `output_parsing`. It will add events for which modules are being used (`Predict`, `ChainOfThought`) and log the full, raw prompt/completion data as span attributes.

*   **`Altar` Instrumentation:** The host application's tool-execution wrapper (as designed in Architecture A) will use `AITrace.span` to wrap every call to `Altar.LATER.Executor`. The span's attributes will include the tool's name, arguments, and the validated result or error. This provides perfect observability into tool usage.

*   **`Snakepit` Instrumentation:** `Snakepit` will be enhanced to accept an `AITrace.Context`. It will extract the `trace_id` and `span_id` and pass them as gRPC metadata to the Python worker. A corresponding Python library will then be able to reconstruct the trace context on the other side, enabling true cross-language distributed tracing. The duration of the gRPC call itself will be captured in a span.

## The End Goal: The "Execution Cinema"

The data generated by `AITrace` is structured to power a rich, interactive debugging UI. This UI is the ultimate user-facing product of the library.

### Features
*   **Waterfall View:** A visual timeline showing the nested spans of a trace, allowing a developer to immediately spot long-running operations.
*   **Context Explorer:** Clicking on any span reveals its full attributes—the exact prompt sent to an LLM, the JSON returned from a tool, the error message from a validation failure.
*   **State Diff:** For spans that include agent state changes, the UI can show a "diff" of the state before and after the operation.
*   **Causal Flow:** The UI will clearly visualize the flow of data and control, making it easy to follow the agent's "train of thought."

This is not just a log viewer; it is a purpose-built, interactive debugger for AI reasoning.