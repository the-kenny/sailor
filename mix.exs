defmodule Sailor.MixProject do
  use Mix.Project

  def project do
    [
      app: :sailor,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Sailor.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:salty, "~> 0.1.3", git: "https://github.com/the-kenny/libsalty.git", branch: "add-ed-to-curve-conversion-functions"},
      {:jason, "~> 1.1"},
    ]
  end
end
