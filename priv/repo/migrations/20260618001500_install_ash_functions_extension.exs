defmodule Conveyor.Repo.Migrations.InstallAshFunctionsExtension do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    execute("""
    CREATE OR REPLACE FUNCTION ash_raise_error(json_data jsonb)
    RETURNS BOOLEAN AS $$
    BEGIN
        RAISE EXCEPTION 'ash_error: %', json_data::text;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    STABLE
    SET search_path = '';
    """)

    execute("""
    CREATE OR REPLACE FUNCTION ash_raise_error(json_data jsonb, type_signal ANYCOMPATIBLE)
    RETURNS ANYCOMPATIBLE AS $$
    BEGIN
        RAISE EXCEPTION 'ash_error: %', json_data::text;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    STABLE
    SET search_path = '';
    """)

    execute("""
    CREATE OR REPLACE FUNCTION ash_required(value ANYCOMPATIBLE, payload jsonb)
    RETURNS ANYCOMPATIBLE AS $$
    BEGIN
      IF value IS NULL THEN
        RETURN ash_raise_error(payload, value);
      END IF;

      RETURN value;
    END;
    $$ LANGUAGE plpgsql
    STABLE
    SET search_path = '';
    """)

    execute("""
    CREATE OR REPLACE FUNCTION uuid_generate_v7()
    RETURNS UUID
    AS $$
    DECLARE
        unix_ts_ms BYTEA;
        uuid_bytes BYTEA;
    BEGIN
        unix_ts_ms = substring(int8send((extract(epoch FROM clock_timestamp()) * 1000)::bigint) from 3);
        uuid_bytes = unix_ts_ms || gen_random_bytes(10);
        uuid_bytes = set_byte(uuid_bytes, 6, (b'0111' || get_byte(uuid_bytes, 6)::bit(4))::bit(8)::int);
        uuid_bytes = set_byte(uuid_bytes, 8, (b'10' || get_byte(uuid_bytes, 8)::bit(6))::bit(8)::int);
        RETURN encode(uuid_bytes, 'hex')::uuid;
    END
    $$
    LANGUAGE plpgsql
    VOLATILE;
    """)
  end

  def down do
    execute("""
    DROP FUNCTION IF EXISTS uuid_generate_v7(),
      ash_raise_error(jsonb),
      ash_raise_error(jsonb, ANYCOMPATIBLE),
      ash_required(ANYCOMPATIBLE, jsonb)
    """)
  end
end
