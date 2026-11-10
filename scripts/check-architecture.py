#!/usr/bin/env python3
"""Validate the SwiftPM target graph and direct Swift imports using the checked-in policy.

This lightweight source guard supplements compiler isolation; it is not a Swift parser.
"""
import json
from pathlib import Path
import re
import subprocess
import sys

REPOSITORY = Path(__file__).resolve().parent.parent
SEMESTER = REPOSITORY / "semester-5"
IMPORT = re.compile(
    r"^\s*(?:@\w+\s+)*(?:(?:public|internal|package)\s+)?import\s+"
    r"(?:(?:class|struct|enum|func|var|let|protocol|typealias)\s+)?(\w+)", re.MULTILINE)


def import_errors(text, allowed):
    return sorted(set(IMPORT.findall(text)) - set(allowed))


def main():
    policy = json.loads((SEMESTER / "architecture.json").read_text())
    manifest = json.loads(subprocess.check_output(
        ["swift", "package", "--package-path", str(SEMESTER / "Engine"), "dump-package"], text=True))
    errors = []
    actual = {target["name"]: target for target in manifest["targets"]}
    expected = policy["targets"]

    if set(actual) != set(expected):
        errors.append(f"Target inventory differs: actual={sorted(actual)}, policy={sorted(expected)}")
    if manifest.get("dependencies"):
        errors.append("External package dependencies require an architecture policy review")

    for name, rule in expected.items():
        if name not in actual:
            continue
        dependencies = []
        for dependency in actual[name]["dependencies"]:
            values = dependency.get("byName") or dependency.get("target")
            if values:
                dependencies.append(values[0])
            else:
                errors.append(f"{name}: unsupported dependency declaration {dependency}")
        if set(dependencies) != set(rule["dependencies"]):
            errors.append(f"{name}: declared dependencies {dependencies} differ from policy {rule['dependencies']}")

    source_count = 0
    for name, rule in policy["applications"].items():
        project = json.loads(subprocess.check_output(
            ["plutil", "-convert", "json", "-o", "-", str(SEMESTER / rule["project"])], text=True))
        objects = project["objects"]
        target = next((item for item in objects.values()
                       if item.get("isa") == "PBXNativeTarget" and item.get("name") == name), None)
        if target is None:
            errors.append(f"{name}: missing Xcode application target")
            continue
        products = [objects[key]["productName"] for key in target.get("packageProductDependencies", [])]
        if set(products) != set(rule["dependencies"]):
            errors.append(f"{name}: Xcode package dependencies {products} differ from policy")

    for name, rule in {**expected, **policy["applications"]}.items():
        folder = SEMESTER / rule["path"]
        if not folder.is_dir():
            errors.append(f"{name}: missing source directory {folder}")
            continue
        allowed = rule["dependencies"] + rule["imports"]
        for path in sorted(folder.rglob("*.swift")):
            source_count += 1
            for imported in import_errors(path.read_text(), allowed):
                errors.append(f"{path.relative_to(REPOSITORY)}: {name} cannot import {imported}")

    # Shared headers are the C/MSL ABI boundary, not an application or platform adapter.
    shared = SEMESTER / expected["GPUShared"]["path"]
    for path in shared.rglob("*"):
        if path.suffix in {".h", ".c"}:
            for included in re.findall(r"#include\s*[<\"]([^>\"]+)", path.read_text()):
                if included not in {"GPUShared.h", "metal_stdlib", "simd/simd.h", "stddef.h"}:
                    errors.append(f"{path.relative_to(REPOSITORY)}: unexpected GPUShared include {included}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    for name, rule in expected.items():
        print(f"{name} -> {', '.join(rule['dependencies']) or '(none)'}")
    print(f"Architecture verified: {len(expected)} package targets, {source_count} Swift files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
