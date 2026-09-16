#!/usr/bin/env bash
# Build wrapper for the godot-slopworks fork.
#
# ALWAYS build through this script, never bare `scons`.
#
# It stamps the fork's own version status onto the build. Without it, our engine and our
# GodotSharp NuGet packages claim the exact version and package IDs that upstream Godot
# publishes (e.g. Godot.NET.Sdk 4.7.3-rc), so a locally built package silently shadows the
# official one in ~/.nuget/packages for every project on this machine.
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
