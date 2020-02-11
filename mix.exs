defmodule Sailor.MixProject do
  use Mix.Project

  def project do
    [
      app: :sailor,
      version: "0.1.0",
      elixir: "~> 1.10.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Sailor.Application, []},
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:salty, "~> 0.1.3", git: "https://github.com/the-kenny/libsalty.git", branch: "add-ed-to-curve-conversion-functions"},
      {:jason, "~> 1.1"},
      {:jsone, "~> 1.5"},
      {:exqlite, git: "git@github.com:the-kenny/exqlite.git"},
      {:poolboy, "~> 1.5.2"},
      {:worker_pool, "~> 4.0"},
      {:gen_stage, "~> 0.14.2"},

      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false},
    ]
  end
end
