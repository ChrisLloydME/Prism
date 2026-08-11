#!/bin/sh

set -eu

app_bundle="${1:?usage: verify-qt-runtime.sh /path/to/Prism.app}"
executable="$app_bundle/Contents/MacOS/Prism"
frameworks="$app_bundle/Contents/Frameworks"

if [ ! -x "$executable" ] || [ ! -d "$frameworks" ]; then
    echo "error: Prism runtime bundle is incomplete: $app_bundle" >&2
    exit 1
fi

scan_file() {
    binary="$1"
    if ! file "$binary" | grep -q 'Mach-O'; then
        return
    fi
    forbidden="$(otool -l "$binary" | awk '
        $1 == "cmd" {
            wanted = $2 == "LC_LOAD_DYLIB" || $2 == "LC_LOAD_WEAK_DYLIB" \
                || $2 == "LC_REEXPORT_DYLIB" || $2 == "LC_LAZY_LOAD_DYLIB" \
                || $2 == "LC_LOAD_UPWARD_DYLIB"
        }
        wanted && $1 == "name" { print $2; wanted = 0 }
    ' | grep -E '^/(opt/homebrew|usr/local)/' || true)"
    if [ -n "$forbidden" ]; then
        echo "error: Unbundled package-manager dependency in $binary" >&2
        echo "$forbidden" >&2
        exit 1
    fi
}

scan_file "$executable"
find "$frameworks" -type f -print | while IFS= read -r candidate; do
    scan_file "$candidate"
done

if ! otool -L "$executable" | grep -Eq '@(rpath|executable_path/\.\./Frameworks)/QtCore\.framework/Versions/A/QtCore' \
    || ! otool -L "$executable" | grep -Eq '@(rpath|executable_path/\.\./Frameworks)/QtNetwork\.framework/Versions/A/QtNetwork'; then
    echo "error: Prism executable does not reference bundled Qt frameworks" >&2
    exit 1
fi

echo "Qt runtime closure verified: $app_bundle"
