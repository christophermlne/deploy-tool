defmodule Mix.Tasks.Deploy.Mermaid do
  @moduledoc """
  Generate a Mermaid diagram for the deployment workflow.

  ## Usage

      mix deploy.mermaid [options]

  ## Options

      --expand, -e      Expand sub-reactors inline (shows all steps)
      --describe, -d    Include step descriptions
      --output, -o      Output file path (default: full_deploy.mmd)
      --format, -f      Output format: mermaid (default), copy, url

  ## Examples

      # Generate expanded diagram to file
      mix deploy.mermaid --expand

      # Output to terminal for copy-paste
      mix deploy.mermaid --expand --format copy

      # Save to specific file with descriptions
      mix deploy.mermaid --expand --describe --output docs/workflow.mmd
  """

  use Mix.Task

  @shortdoc "Generate Mermaid diagram for the deployment workflow"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    # Pass through to reactor.mermaid with our reactor module
    Mix.Task.run("reactor.mermaid", ["Deploy.Reactors.FullDeploy" | args])
  end
end
