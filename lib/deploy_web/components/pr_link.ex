defmodule DeployWeb.Components.PRLink do
  @moduledoc """
  PR link component with popover hook.

  Renders a GitHub PR link that shows a popover with PR details on hover.
  Requires the PRPopover JS hook to be registered in app.js.
  """

  use Phoenix.Component

  attr :number, :integer, required: true
  attr :context, :string, required: true
  attr :class, :string, default: "text-indigo-600 hover:underline"
  slot :inner_block

  def pr_link(assigns) do
    ~H"""
    <a
      href={pr_url(@number)}
      target="_blank"
      phx-hook="PRPopover"
      id={"pr-#{@context}-#{@number}"}
      data-pr-number={@number}
      class={@class}
    >
      <%= render_slot(@inner_block) || "##{@number}" %>
    </a>
    """
  end

  defp pr_url(pr_number) do
    owner = Deploy.Config.github_owner()
    repo = Deploy.Config.github_repo()
    "https://github.com/#{owner}/#{repo}/pull/#{pr_number}"
  end
end
