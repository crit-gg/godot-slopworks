#!/usr/bin/env python3
# Runs modules/mono/build_scripts/build_assemblies.py with the fork's package versions.
# SLOP_PACKAGE_SUFFIX is appended to every GodotSharp package version, e.g. 4.7.2-slopworks-1a2b3c4.
# Usage: ./build_packages.py [build_assemblies.py args...]

import os
import re
import sys

root_dir = os.path.dirname(os.path.abspath(__file__))
os.environ.setdefault("GODOT_VERSION_STATUS", "slopworks")

sys.path.insert(0, os.path.join(root_dir, "modules", "mono", "build_scripts"))
import build_assemblies  # noqa: E402

suffix = os.environ.get("SLOP_PACKAGE_SUFFIX", "")
generate_versions = build_assemblies.generate_sdk_package_versions


def generate_suffixed_versions():
    generate_versions()
    if not suffix:
        return

    props_path = os.path.join(root_dir, "modules", "mono", "SdkPackageVersions.props")
    with open(props_path, encoding="utf-8") as f:
        props = f.read()

    props = re.sub(
        r"(<PackageVersion_(?:GodotSharp|Godot_NET_Sdk|Godot_SourceGenerators)>)([^<]+)(<)",
        lambda m: f"{m.group(1)}{m.group(2)}-{suffix}{m.group(3)}",
        props,
    )

    with open(props_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(props)


build_assemblies.generate_sdk_package_versions = generate_suffixed_versions
print(f"==> GODOT_VERSION_STATUS={os.environ['GODOT_VERSION_STATUS']} SLOP_PACKAGE_SUFFIX={suffix}")
build_assemblies.main()
