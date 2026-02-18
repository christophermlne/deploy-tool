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
      --readme          Insert/update diagram in README.md

  ## Examples

      # Generate expanded diagram to file
      mix deploy.mermaid --expand

      # Output to terminal for copy-paste
      mix deploy.mermaid --expand --format copy

      # Insert expanded diagram into README.md
      mix deploy.mermaid --expand --readme

  ## README Integration

  When using --readme, the diagram is inserted between marker comments:

      <!-- MERMAID_DIAGRAM_START -->
      ```mermaid
      ...
      ```
      <!-- MERMAID_DIAGRAM_END -->

  Add these markers to your README.md where you want the diagram to appear.
  The task will replace everything between the markers with the updated diagram.
  """

  use Mix.Task

  @shortdoc "Generate Mermaid diagram for the deployment workflow"

  @start_marker "<!-- MERMAID_DIAGRAM_START -->"
  @end_marker "<!-- MERMAID_DIAGRAM_END -->"

  @switches [
    expand: :boolean,
    describe: :boolean,
    output: :string,
    format: :string,
    readme: :boolean
  ]

  @aliases [
    e: :expand,
    d: :describe,
    o: :output,
    f: :format
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if opts[:readme] do
      update_readme(opts)
    else
      # Pass through to reactor.mermaid
      reactor_args = build_reactor_args(opts)
      Mix.Task.run("reactor.mermaid", ["Deploy.Reactors.FullDeploy" | reactor_args])
    end
  end

  defp update_readme(opts) do
    readme_path = "README.md"

    with {:ok, readme} <- File.read(readme_path),
         {:ok, diagram} <- generate_diagram(opts),
         {:ok, updated} <- insert_diagram(readme, diagram) do
      File.write!(readme_path, updated)
      Mix.shell().info("Updated #{readme_path} with Mermaid diagram")
    else
      {:error, :enoent} ->
        Mix.shell().error("README.md not found")

      {:error, :no_markers} ->
        Mix.shell().error("""
        Could not find diagram markers in README.md.

        Add these markers where you want the diagram:

            #{@start_marker}
            #{@end_marker}
        """)

      {:error, reason} ->
        Mix.shell().error("Failed to generate diagram: #{inspect(reason)}")
    end
  end

  defp generate_diagram(opts) do
    mermaid_opts = [
      expand?: opts[:expand] || false,
      describe?: opts[:describe] || false
    ]

    case Reactor.Mermaid.to_mermaid(Deploy.Reactors.FullDeploy, mermaid_opts) do
      {:ok, iodata} -> {:ok, IO.iodata_to_binary(iodata)}
      error -> error
    end
  end

  defp insert_diagram(readme, diagram) do
    pattern = ~r/#{Regex.escape(@start_marker)}.*#{Regex.escape(@end_marker)}/s

    if Regex.match?(pattern, readme) do
      replacement = """
      #{@start_marker}
      ```mermaid
      #{String.trim(diagram)}
      ```
      #{@end_marker}\
      """

      updated = Regex.replace(pattern, readme, replacement)
      {:ok, updated}
    else
      {:error, :no_markers}
    end
  end

  defp build_reactor_args(opts) do
    args = []
    args = if opts[:expand], do: ["--expand" | args], else: args
    args = if opts[:describe], do: ["--describe" | args], else: args
    args = if opts[:output], do: ["--output", opts[:output] | args], else: args
    args = if opts[:format], do: ["--format", opts[:format] | args], else: args
    args
  end
end
