#!/usr/bin/env python3
"""Check shipped scripts, documentation links and accidental placeholders."""
import ast
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def main():
    for script in (ROOT / "scripts").glob("*.py"):
        ast.parse(script.read_text(), filename=str(script))
    text = (ROOT / "README.md").read_text()
    for target in re.findall(r"\]\(([^)]+)\)", text):
        if "://" not in target and not target.startswith("#"):
            assert (ROOT / target.split("#")[0]).exists(), f"Broken local link: {target}"
    assert not re.search(r"\b(TODO|FIXME|TBD)\b|<your-|<supported-", text), "Unfinished README placeholder."
    assert not re.search(r"\b\d{12}\b", text), "Do not publish real account identifiers."
    for root in ["console", "automq-example/instance", "automq-example/smoke"]:
        for path in (ROOT / root).glob("*.tf"):
            assert "clientSecret =" not in path.read_text(), f"Literal CONFIG secret in {path}."
    print("PASS: script syntax, local documentation links and placeholder checks.")

if __name__ == "__main__":
    main()
