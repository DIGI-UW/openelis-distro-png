#!/usr/bin/env bash
# Execute the PNG fixtures with the exact released Bridge classes used by Compose.
# Requires Docker and Java 21 (JAVA_HOME is honored). No upstream checkout needed.
set -euo pipefail
cd "$(dirname "$0")/.."
image=$(sed -n 's/^[[:space:]]*image: \(.*\)/\1/p' docker-compose.analyzers.yml | head -n 1)
work=$(mktemp -d)
container=
cleanup() {
  if [[ -n "$container" ]]; then docker rm -v "$container" >/dev/null; fi
  rm -rf "$work"
}
trap cleanup EXIT
container=$(docker create --platform linux/amd64 "$image")
docker cp "$container:/app/openelis-analyzer-bridge.jar" "$work/bridge.jar"
java_bin=${JAVA_HOME:+$JAVA_HOME/bin/}
(cd "$work" && "${java_bin}jar" xf bridge.jar BOOT-INF/classes BOOT-INF/lib)
cp="$work/BOOT-INF/classes:$work/BOOT-INF/lib/*"
"${java_bin}javac" -proc:none -cp "$cp" -d "$work/classes" tests/PngProfileCheck.java
"${java_bin}java" -cp "$work/classes:$cp" org.itech.ahb.profile.PngProfileCheck configs/analyzer-catalog "$work/catalog"
