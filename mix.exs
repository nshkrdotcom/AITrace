# `build_support/` is not shipped in the published package, so its absence is
# how this file knows it is running inside a consumer's deps/ rather than in a
# source checkout. Guard on the file, not on a directory shape: a shape test
# breaks when the repo is vendored at a different depth or used as a git dep.
workspace_helper = Path.expand("build_support/dependency_sources.exs", __DIR__)

if File.regular?(workspace_helper) and not Code.ensure_loaded?(DependencySources) do
  Code.require_file(workspace_helper)
end

defmodule AITrace.MixProject do
  use Mix.Project

  @workspace_checkout? File.regular?(Path.expand("build_support/dependency_sources.exs", __DIR__))

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/AITrace"

  def project do
    [
      app: :aitrace,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "AITrace",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        credo: :dev,
        dialyzer: :dev,
        docs: :dev
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {AITrace.Application, []}
    ]
  end

  defp deps do
    [
      workspace_dep(:ground_plane_contracts, "~> 0.1.0", override: true),
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.3"},
      {:ex_doc, "~> 0.40.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    The unified observability layer for the AI Control Plane, delivering full-fidelity tracing for AI agent reasoning, tool calls, and state transitions.
    """
  end

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "dialyzer --format short",
        "docs"
      ]
    ]
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
        "guides/generalized_stack.md",
        "guides/qc_and_operations.md",
        "guides/code_smell_remediation.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: [
          "README.md",
          "guides/generalized_stack.md",
          "guides/qc_and_operations.md",
          "guides/code_smell_remediation.md"
        ],
        "Release Notes": ["CHANGELOG.md"],
        Legal: ["LICENSE"]
      ]
    ]
  end


  # In a source checkout the registry decides the source (path first). In a
  # published package there is no registry, and the requirement stated here is
  # the whole answer.
  defp workspace_dep(app, hex_requirement, opts \\ []) do
    if @workspace_checkout? do
      apply(DependencySources, :dep, [app, __DIR__, opts])
    else
      if opts == [], do: {app, hex_requirement}, else: {app, hex_requirement, opts}
    end
  end

  defp package do
    [
      name: "aitrace",
      description: description(),
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE assets guides AGENTS.md),
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
