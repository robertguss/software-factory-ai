defmodule Conveyor.Repo.Migrations.AllowPriorFindingsInstructionSource do
  use Ecto.Migration

  @old_source_kinds "source_kind IN ('system', 'project', 'plan', 'brief', 'agents_md', 'repo_file', 'tool_output')"

  @new_source_kinds "source_kind IN ('system', 'project', 'plan', 'brief', 'prior_findings', 'agents_md', 'repo_file', 'tool_output')"

  def up do
    drop constraint(:instruction_sources, :instruction_sources_source_kind_must_be_known)

    create constraint(:instruction_sources, :instruction_sources_source_kind_must_be_known,
             check: @new_source_kinds
           )
  end

  def down do
    drop constraint(:instruction_sources, :instruction_sources_source_kind_must_be_known)

    create constraint(:instruction_sources, :instruction_sources_source_kind_must_be_known,
             check: @old_source_kinds
           )
  end
end
