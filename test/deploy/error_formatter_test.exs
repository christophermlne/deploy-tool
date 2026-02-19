defmodule Deploy.ErrorFormatterTest do
  use ExUnit.Case, async: true

  alias Deploy.ErrorFormatter

  describe "format/1" do
    test "passes through simple binary strings" do
      assert ErrorFormatter.format("some error") == "some error"
    end

    test "parses validation failures from raw inspect strings (backwards compat)" do
      # This simulates an error stored in the database before the formatter was added
      raw_string = ~s|%Reactor.Error.Invalid.RunStepError{error: %{validation_failures: [%{title: "Feat 2", number: 33, reasons: [:ci_check_failed, :no_approval]}, %{title: "Feat 1", number: 34, reasons: [:ci_check_failed, :no_approval]}]}}|

      result = ErrorFormatter.format(raw_string)

      assert result =~ "PR #33 (Feat 2): CI checks failed, not approved"
      assert result =~ "PR #34 (Feat 1): CI checks failed, not approved"
    end

    test "formats :cancelled atom" do
      assert ErrorFormatter.format(:cancelled) == "Deployment was cancelled"
    end

    test "formats validation failures map" do
      error = %{
        validation_failures: [
          %{title: "Feat 2", number: 33, reasons: [:ci_check_failed, :no_approval]},
          %{title: "Feat 1", number: 34, reasons: [:ci_check_failed, :no_approval]}
        ]
      }

      result = ErrorFormatter.format(error)

      assert result =~ "PR #33 (Feat 2): CI checks failed, not approved"
      assert result =~ "PR #34 (Feat 1): CI checks failed, not approved"
    end

    test "extracts error from Reactor.Error.Invalid.RunStepError" do
      # Simulate the structure of a RunStepError
      error = %{
        __struct__: Reactor.Error.Invalid.RunStepError,
        error: %{
          validation_failures: [
            %{title: "Test PR", number: 1, reasons: [:no_approval]}
          ]
        },
        step: %{},
        splode: nil
      }

      result = ErrorFormatter.format(error)
      assert result =~ "PR #1 (Test PR): not approved"
    end

    test "extracts errors from Reactor.Error.Invalid with errors list (composed reactors)" do
      # Simulate the nested structure from compose steps
      error = %{
        __struct__: Reactor.Error.Invalid,
        errors: [
          %{
            __struct__: Reactor.Error.Invalid.RunStepError,
            error: %{
              validation_failures: [
                %{title: "Feat 2", number: 33, reasons: [:ci_check_failed, :no_approval]}
              ]
            },
            step: %{},
            splode: nil
          }
        ],
        splode: nil
      }

      result = ErrorFormatter.format(error)
      assert result =~ "PR #33 (Feat 2): CI checks failed, not approved"
    end

    test "parses nested errors from raw inspect strings (compose steps backwards compat)" do
      raw_string = ~s|%Reactor.Error.Invalid{errors: [%Reactor.Error.Invalid.RunStepError{error: %{validation_failures: [%{title: "Feat 2", number: 33, reasons: [:ci_check_failed, :no_approval]}]}}]}|

      result = ErrorFormatter.format(raw_string)
      assert result =~ "PR #33 (Feat 2): CI checks failed, not approved"
    end

    test "formats CI failed with check names" do
      error = %{
        validation_failures: [
          %{number: 1, title: "PR", reasons: [{:ci_failed, ["lint", "test"]}]}
        ]
      }

      result = ErrorFormatter.format(error)
      assert result =~ "CI failed: lint, test"
    end

    test "formats various failure reasons" do
      reasons = [
        {:no_approval, "not approved"},
        {:ci_pending, "CI checks pending"},
        {:ci_check_failed, "CI checks failed"},
        {:has_conflicts, "has merge conflicts"},
        {:not_mergeable, "not mergeable"}
      ]

      for {reason, expected_text} <- reasons do
        error = %{validation_failures: [%{number: 1, title: "PR", reasons: [reason]}]}
        assert ErrorFormatter.format(error) =~ expected_text
      end
    end

    test "handles maps with message key" do
      assert ErrorFormatter.format(%{message: "Custom error"}) == "Custom error"
    end

    test "handles maps with reason key" do
      assert ErrorFormatter.format(%{reason: "Some reason"}) == "Some reason"
    end

    test "falls back to inspect for unknown structures" do
      result = ErrorFormatter.format({:unknown, :error})
      assert is_binary(result)
    end
  end
end
