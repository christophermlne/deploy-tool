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
  def format(error) when is_binary(error) do
    # Try to extract validation failures from raw inspect strings (backwards compat)
    case extract_validation_failures_from_string(error) do
      {:ok, failures} -> format_validation_failures(failures)
      :error -> error
    end
  end

  def format(:cancelled), do: "Deployment was cancelled"

  # Handle Reactor.Error.Invalid with errors list (wrapper for composed reactors)
  def format(%{__struct__: struct, errors: errors}) when is_atom(struct) and is_list(errors) do
    struct_name = Atom.to_string(struct)

    if String.contains?(struct_name, "Reactor.Error") do
      # Format each error in the list and join them
      errors
      |> Enum.map(&format/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")
    else
      inspect(%{__struct__: struct, errors: errors}, pretty: true, limit: 5)
    end
  end

  # Handle Reactor error structs with single error - check by module name pattern
  def format(%{__struct__: struct, error: inner_error}) when is_atom(struct) do
    struct_name = Atom.to_string(struct)

    if String.contains?(struct_name, "Reactor.Error") do
      format(inner_error)
    else
      # Not a Reactor error, fall through to other handlers
      format_struct_fallback(%{__struct__: struct, error: inner_error})
    end
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

  # Helper for structs that aren't Reactor errors but have error key
  defp format_struct_fallback(%{error: inner_error}), do: format(inner_error)

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

  # Try to extract validation failures from a raw inspect string
  # This handles errors stored before the formatter was added
  # Works for both Reactor.Error.Invalid (with errors: [...]) and
  # Reactor.Error.Invalid.RunStepError (with error: %{...})
  defp extract_validation_failures_from_string(error_string) do
    # Look for validation_failures pattern in the string
    # Pattern: validation_failures: [%{title: "...", number: N, reasons: [...]}]
    with true <- String.contains?(error_string, "validation_failures"),
         {:ok, failures} <- parse_validation_failures(error_string) do
      {:ok, failures}
    else
      _ -> :error
    end
  end

  defp parse_validation_failures(error_string) do
    # Use regex to extract the validation failures list
    # Match patterns like: %{title: "Feat 2", number: 33, reasons: [:ci_check_failed, :no_approval]}
    regex = ~r/%\{title: "([^"]+)", number: (\d+), reasons: \[([^\]]+)\]\}/

    failures =
      Regex.scan(regex, error_string)
      |> Enum.map(fn [_full, title, number, reasons_str] ->
        reasons = parse_reasons(reasons_str)
        %{title: title, number: String.to_integer(number), reasons: reasons}
      end)

    if failures == [] do
      :error
    else
      {:ok, failures}
    end
  end

  defp parse_reasons(reasons_str) do
    # Parse comma-separated atoms like ":ci_check_failed, :no_approval"
    reasons_str
    |> String.split(", ")
    |> Enum.map(&parse_single_reason/1)
  end

  defp parse_single_reason(":no_approval"), do: :no_approval
  defp parse_single_reason(":ci_pending"), do: :ci_pending
  defp parse_single_reason(":ci_check_failed"), do: :ci_check_failed
  defp parse_single_reason(":has_conflicts"), do: :has_conflicts
  defp parse_single_reason(":not_mergeable"), do: :not_mergeable
  defp parse_single_reason(reason_str) do
    # Try to convert to atom, or return as string
    if String.starts_with?(reason_str, ":") do
      reason_str |> String.trim_leading(":") |> String.to_atom()
    else
      reason_str
    end
  end
end
