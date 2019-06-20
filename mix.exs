defmodule Sailor.MixProject do
  use Mix.Project

  def project do
    [
      app: :sailor,
      version: "0.1.0",
      elixir: "~> 1.9.0-rc.0",
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
      {:jsone, git: "https://github.com/the-kenny/jsone.git", branch: "empty-array-formatting"},
      {:sqlitex, "~> 1.7"},
      {:poolboy, "~> 1.5.2"},
    ]
  end
end
