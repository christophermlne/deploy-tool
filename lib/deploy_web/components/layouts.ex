defmodule DeployWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.
  """

  use DeployWeb, :html

  embed_templates "layouts/*"
end
