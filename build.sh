#!/usr/bin/env bash
# Build wrapper for the godot-slopworks fork.
#
# ALWAYS build through this script, never bare `scons`.
#
# It stamps the fork's own version status onto the build. Without it, our engine and our
# GodotSharp NuGet packages claim the exact version and package IDs that upstream Godot
# publishes. This branch is rooted at the 4.7.2-stable tag, where version.py already reads
# status = "stable", so an unmarked build produces Godot.NET.Sdk 4.7.2 -- the very package
# Godot shipped -- and silently shadows it in ~/.nuget/packages for every project on this
# machine. There is no -rc suffix left to tell the two apart.
#
# Usage:  ./build.sh [scons args...]
#   ./build.sh target=editor module_mono_enabled=yes -j$(nproc)
#   ./build.sh target=template_release module_mono_enabled=yes -j$(nproc)
set -euo pipefail

# Upstream's major.minor.patch is kept, so compatibility stays readable at a glance. Only
# the status is ours. methods.py:160 reads this and overrides version.py, which means no
# patch to version.py and therefore no conflict on upstream version bumps.
export GODOT_VERSION_STATUS="${GODOT_VERSION_STATUS:-slopworks}"

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "==> GODOT_VERSION_STATUS=$GODOT_VERSION_STATUS"
exec scons platform="${PLATFORM:-linuxbsd}" "$@"
