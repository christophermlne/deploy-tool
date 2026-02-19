defmodule Deploy.ErrorFormatter do
  @moduledoc """
  Formats deployment errors into human-readable messages.

  Handles Reactor errors and extracts meaningful information from
  nested error structures.
  """

  @doc """
  Formats an error into a human-readable string.

  Handles various error types:
  - Binary strings (pass through)
  - Reactor.Error.Invalid.RunStepError with validation_failures
  - Maps with :message or :reason keys
  - Atoms like :cancelled
  - Fallback to inspect for unknown structures
  """
  @spec format(term()) :: String.t()
  def format(error) when is_binary(error), do: error

  def format(:cancelled), do: "Deployment was cancelled"

  # Handle Reactor.Error.Invalid.RunStepError
  def format(%{__struct__: struct, error: inner_error})
      when struct == Reactor.Error.Invalid.RunStepError do
    format(inner_error)
  end

  # Handle validation failures map
  def format(%{validation_failures: failures}) when is_list(failures) do
    format_validation_failures(failures)
  end

  # Handle generic error maps with message
  def format(%{message: message}) when is_binary(message), do: message

  # Handle generic error maps with reason
  def format(%{reason: reason}) when is_binary(reason), do: reason

  # Handle exception structs
  def format(%{__exception__: true, message: message}) when is_binary(message), do: message

  # Handle tuples like {:error, reason}
  def format({:error, reason}), do: format(reason)

  # Fallback - try to make inspect output cleaner
  def format(error) do
    inspect(error, pretty: true, limit: 5)
  end

  @doc """
  Formats a list of PR validation failures into a readable message.
  """
  def format_validation_failures(failures) do
    failures
    |> Enum.map(&format_pr_failure/1)
    |> Enum.join("\n\n")
  end

  defp format_pr_failure(%{number: number, title: title, reasons: reasons}) do
    reason_text =
      reasons
      |> Enum.map(&format_reason/1)
      |> Enum.join(", ")

    "PR ##{number} (#{title}): #{reason_text}"
  end

  defp format_pr_failure(%{number: number, reasons: reasons}) do
    reason_text =
      reasons
      |> Enum.map(&format_reason/1)
      |> Enum.join(", ")

    "PR ##{number}: #{reason_text}"
  end

  defp format_reason(:no_approval), do: "not approved"
  defp format_reason(:ci_pending), do: "CI checks pending"
  defp format_reason(:ci_check_failed), do: "CI checks failed"
  defp format_reason({:ci_failed, checks}) when is_list(checks) do
    "CI failed: #{Enum.join(checks, ", ")}"
  end
  defp format_reason(:has_conflicts), do: "has merge conflicts"
  defp format_reason(:not_mergeable), do: "not mergeable"
  defp format_reason(reason) when is_atom(reason) do
    reason |> Atom.to_string() |> String.replace("_", " ")
  end
  defp format_reason(reason), do: inspect(reason)
end
