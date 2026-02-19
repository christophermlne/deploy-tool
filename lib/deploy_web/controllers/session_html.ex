defmodule DeployWeb.SessionHTML do
  @moduledoc """
  View module for session templates.
  """

  use DeployWeb, :html

  embed_templates "session_html/*"
end
