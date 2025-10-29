# AITrace Basic Usage Example
#
# This example demonstrates how to use AITrace to instrument an AI agent workflow.
#
# Run with: mix run examples/basic_usage.exs

require AITrace

# Configure exporters
Application.put_env(:aitrace, :exporters, [
  {AITrace.Exporter.Console, verbose: true}
])

defmodule ExampleAgent do
  @moduledoc """
  A simple AI agent that demonstrates AITrace instrumentation.
  """

  require AITrace

  def handle_user_request(user_message) do
    AITrace.trace "agent.handle_request" do
      AITrace.add_event("request_received", %{message_length: String.length(user_message)})

      # Simulate reasoning process
      AITrace.span "reasoning" do
        AITrace.with_attributes(%{model: "gpt-4", temperature: 0.7})

        thoughts = think_about(user_message)
        AITrace.add_event("reasoning_complete", %{thought_count: length(thoughts)})

        thoughts
      end

      # Simulate tool execution
      result =
        AITrace.span "tool_execution" do
          AITrace.with_attributes(%{tool: "web_search"})

          execute_tool("web_search", user_message)
        end

      # Simulate response generation
      AITrace.span "response_generation" do
        AITrace.with_attributes(%{tokens: 150})

        generate_response(result)
      end
    end
  end

  defp think_about(message) do
    # Simulate LLM latency
    Process.sleep(10)
    ["thought 1", "thought 2", "thought 3"]
  end

  defp execute_tool(tool_name, query) do
    # Simulate tool execution
    Process.sleep(5)
    %{tool: tool_name, query: query, results: ["result1", "result2"]}
  end

  defp generate_response(tool_result) do
    # Simulate LLM latency
    Process.sleep(8)
    "Based on the search results, here's my answer..."
  end
end

# Example usage
IO.puts("\n=== Running AITrace Example ===\n")

response = ExampleAgent.handle_user_request("What is Elixir?")

IO.puts("\n=== Agent Response ===")
IO.puts(response)
IO.puts("\n=== Trace output above shows the complete execution flow ===\n")
