defmodule Conveyor.Repo.Migrations.UpdatePolicyProfileMaintenance do
  use Ecto.Migration

  def up do
    drop constraint(:policies, :policies_profile_must_be_known)

    execute("""
    UPDATE policies
    SET profile = 'maintenance'
    WHERE profile = 'dangerous_maintenance'
    """)

    create constraint(:policies, :policies_profile_must_be_known,
             check: "profile IN ('explore', 'implement', 'verify', 'release', 'maintenance')"
           )
  end

  def down do
    drop constraint(:policies, :policies_profile_must_be_known)

    execute("""
    UPDATE policies
    SET profile = 'dangerous_maintenance'
    WHERE profile = 'maintenance'
    """)

    create constraint(:policies, :policies_profile_must_be_known,
             check:
               "profile IN ('explore', 'implement', 'verify', 'release', 'dangerous_maintenance')"
           )
  end
end
