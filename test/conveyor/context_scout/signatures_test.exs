defmodule Conveyor.ContextScout.SignaturesTest do
  @moduledoc "aabq.2: language-neutral, regex-based interface signature extraction."
  use ExUnit.Case, async: true

  alias Conveyor.ContextScout.Signatures

  test "extracts Elixir module head, @spec, public def/defmacro — but not defp" do
    content = """
    defmodule Foo do
      @spec bar(integer()) :: integer()
      def bar(x), do: x + 1
      defp secret(x), do: x
      defmacro mac(x), do: x
    end
    """

    sigs = Signatures.extract(content, "lib/foo.ex")

    assert sigs =~ "defmodule Foo do"
    assert sigs =~ "@spec bar"
    assert sigs =~ "def bar(x)"
    assert sigs =~ "defmacro mac"
    refute sigs =~ "defp secret"
  end

  test "extracts JS/TS exports, functions, classes, interfaces — not imports/consts" do
    content = """
    import x from 'y'
    export function create(a) { return a }
    class Widget {}
    export interface Opts { id: string }
    const internal = 1
    """

    sigs = Signatures.extract(content, "src/app.ts")

    assert sigs =~ "export function create"
    assert sigs =~ "class Widget"
    assert sigs =~ "export interface Opts"
    refute sigs =~ "import x"
    refute sigs =~ "const internal"
  end

  test "extracts Python def/class — not imports" do
    content = """
    import os
    class Task:
        def run(self):
            pass
    async def fetch(url):
        pass
    """

    sigs = Signatures.extract(content, "svc/main.py")

    assert sigs =~ "class Task"
    assert sigs =~ "def run(self)"
    assert sigs =~ "async def fetch"
    refute sigs =~ "import os"
  end

  test "unknown language or no signatures returns nil so the caller falls back to head" do
    assert Signatures.extract("just prose\nmore prose", "notes.txt") == nil
    assert Signatures.extract("# a comment only\nprint('hi')\n", "svc/app.py") == nil
    assert Signatures.language("x.rs") == nil
    assert Signatures.language("x.ex") == :elixir
    assert Signatures.language("x.TSX") == :javascript
  end
end
