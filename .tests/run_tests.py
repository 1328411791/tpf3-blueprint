"""Run the Lua contract tests with lupa (only a development dependency)."""
import os
import json
import re
from pathlib import Path
import sys

if os.environ.get("BLUEPRINT_TEST_DEPS"):
    sys.path.insert(0, os.environ["BLUEPRINT_TEST_DEPS"])
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().ROOT = root.as_posix()
translations = json.loads((root / "strings.json").read_text(encoding="utf-8"))
assert set(translations["en"]) == set(translations["zh_CN"])
for language, entries in translations.items():
    for key, value in entries.items():
        assert isinstance(value, str) and value, (language, key)
        assert set(re.findall(r"\{(\w+)\}", value)) == set(re.findall(r"\{(\w+)\}", translations["en"][key])), (language, key)
lua.globals().TRANSLATIONS = lua.table_from(translations, recursive=True)
lua.execute('''
testLanguage = "zh_CN"
function _(key)
    return (TRANSLATIONS[testLanguage] or {})[key] or TRANSLATIONS.en[key] or key
end
''')
# Every new Lua file must compile, including resource descriptors.
for path in sorted((root / "content").rglob("*")):
    if path.suffix == ".lua" or path.name.endswith(".metacon.tl"):
        source = path.read_text(encoding="utf-8-sig")
        lua.execute("assert(load(...))", source)
        for key in re.findall(r'"(BLUEPRINT_[A-Z_]+)"', source):
            assert key in translations["en"], (path, key)
lua.execute((root / "tests" / "test_blueprint.lua").read_text(encoding="utf-8-sig"))
