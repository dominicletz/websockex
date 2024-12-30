defmodule WebSockex.Mixfile do
  use Mix.Project

  def project do
    [
      aliases: aliases(),
      app: :websockex,
      name: "WebSockex",
      version: "0.5.0",
      elixir: "~> 1.11",
      description: "An Elixir WebSocket client",
      source_url: "https://github.com/Azolo/websockex",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: [~c"lib", ~c"test/support"]
  defp elixirc_paths(_), do: [~c"lib"]

  def application do
    applications = [:logger, :ssl, :crypto] ++ applications(otp_release())
    [extra_applications: applications, mod: {WebSockex.Application, []}]
  end

  defp applications(otp_release) when otp_release >= 21 do
    [:telemetry]
  end

  defp applications(_), do: []

  defp aliases do
    [
      lint: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --only warning",
        "dialyzer"
      ]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:cowboy, "~> 2.9", only: :test},
      {:plug_cowboy, "~> 2.5", only: :test},
      {:plug, "~> 1.12", only: :test},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ] ++ optional_deps(otp_release())
  end

  defp optional_deps(otp_release) when otp_release >= 21 do
    [{:telemetry, "~> 1.0"}]
  end

  defp optional_deps(_), do: []

  defp package do
    %{
      name: :websockex_wt,
      licenses: ["MIT"],
      maintainers: ["Dominic Letz"],
      links: %{"GitHub" => "https://github.com/dominicletz/websockex"}
    }
  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme"
    ]
  end

  defp otp_release do
    :erlang.system_info(:otp_release) |> to_string() |> String.to_integer()
  end
end
