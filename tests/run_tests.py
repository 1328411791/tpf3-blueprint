"""Run the Lua contract tests with lupa (only a development dependency)."""
import os
from pathlib import Path
import sys

if os.environ.get("BLUEPRINT_TEST_DEPS"):
    sys.path.insert(0, os.environ["BLUEPRINT_TEST_DEPS"])
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().ROOT = root.as_posix()
# Every new Lua file must compile, including resource descriptors.
for path in sorted((root / "content").rglob("*")):
    if path.suffix == ".lua" or path.name.endswith(".metacon.tl"):
        lua.execute("assert(load(...))", path.read_text(encoding="utf-8-sig"))
lua.execute((root / "tests" / "test_blueprint.lua").read_text(encoding="utf-8-sig"))
