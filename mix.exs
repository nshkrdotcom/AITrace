defmodule Aitrace.MixProject do
  use Mix.Project

  def project do
    [
      app: :aitrace,
      version: "0.0.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "The unified observability layer for the AI Control Plane.",
      package: [
        maintainers: ["nshkrdotcom <ZeroTrust@NSHkr.com>"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/nshkrdotcom/AITrace"}
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AITrace.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
