defmodule Conveyor.PlanningAdmissionTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.Admission

  test "agentic planning requires an active grant covering roles adapters environment verification and autonomy" do
    request = %{
      roles: ["planner", "reviewer"],
      adapters: ["primary-live"],
      environment: "ci-linux",
      verification: ["schema", "unit"],
      autonomy: "team"
    }

    grant = %{
      status: "active",
      roles: ["planner", "reviewer", "implementer"],
      adapters: ["primary-live"],
      environments: ["ci-linux"],
      verification: ["schema", "unit", "integration"],
      max_autonomy: "team"
    }

    assert {:ok,
            %{
              mode: :agentic_planning,
              authority: :approval_eligible,
              approval_authority?: true
            }} = Admission.admit(:agentic_planning, request, grant)
  end

  test "deterministic parse/lint may run without a grant but has no approval authority" do
    assert {:ok,
            %{
              mode: :deterministic_parse_lint,
              authority: :read_only_parse_lint,
              approval_authority?: false
            }} = Admission.admit(:deterministic_parse_lint, %{roles: ["planner"]}, nil)
  end

  test "agentic planning is denied when the grant does not cover requested scope" do
    request = %{
      roles: ["planner"],
      adapters: ["primary-live"],
      environment: "prod",
      verification: ["integration"],
      autonomy: "team"
    }

    grant = %{
      status: "active",
      roles: ["planner"],
      adapters: ["primary-live"],
      environments: ["ci-linux"],
      verification: ["schema"],
      max_autonomy: "local_dev"
    }

    assert {:deny, reasons} = Admission.admit(:agentic_planning, request, grant)
    assert reasons == [:environment_not_covered, :verification_not_covered, :autonomy_not_covered]
  end
end
