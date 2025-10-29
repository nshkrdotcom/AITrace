defmodule AITrace.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/AITrace"

  def project do
    [
      app: :aitrace,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "AITrace",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AITrace.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    The unified observability layer for the AI Control Plane, delivering full-fidelity tracing for AI agent reasoning, tool calls, and state transitions.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "AITrace",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/ai_trace.svg",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ["README.md"],
        "Release Notes": ["CHANGELOG.md"]
      ]
    ]
  end

  defp package do
    [
      name: "aitrace",
      description: description(),
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE assets),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/aitrace",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["nshkrdotcom"]
    ]
  end
end
