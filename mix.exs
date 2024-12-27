defmodule ClusterLoadBalancer.MixProject do
  use Mix.Project

  def project do
    [
      app: :cluster_load_balancer,
      version: "1.0.0",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Load balance resources in your Elixir cluster (like WebSockets after a rolling deploy)",
      package: [
        maintainers: ["Steve Bussey"],
        licenses: ["MIT"],
        links: %{github: "https://github.com/pushex-project/cluster_load_balancer"},
        files: ~w(lib) ++ ~w(mix.exs README.md)
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
