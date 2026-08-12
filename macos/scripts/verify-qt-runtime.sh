#!/bin/sh

set -eu

app_bundle="${1:?usage: verify-qt-runtime.sh /path/to/Prism.app}"
executable="$app_bundle/Contents/MacOS/Prism"
frameworks="$app_bundle/Contents/Frameworks"
maximum_deployment_target="${PRISM_MACOS_DEPLOYMENT_TARGET:-14.0}"

if [ ! -x "$executable" ] || [ ! -d "$frameworks" ]; then
    echo "error: Prism runtime bundle is incomplete: $app_bundle" >&2
    exit 1
fi

scan_file() {
    binary="$1"
    if ! file "$binary" | grep -q 'Mach-O'; then
        return
    fi
    minimum_os="$(otool -l "$binary" | awk '$1 == "minos" { print $2; exit }')"
    if [ -n "$minimum_os" ] && ! awk -v actual="$minimum_os" -v maximum="$maximum_deployment_target" '
        function version_number(version, parts) {
            split(version, parts, ".")
            return (parts[1] * 1000000) + (parts[2] * 1000) + parts[3]
        }
        BEGIN { exit(version_number(actual) <= version_number(maximum) ? 0 : 1) }
    '; then
        echo "error: $binary requires macOS $minimum_os (maximum allowed: $maximum_deployment_target)" >&2
        exit 1
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
backend="$app_bundle/Contents/MacOS/prism_backend"
if [ -e "$backend" ]; then
    if [ ! -x "$backend" ]; then
        echo "error: Prism backend helper is not executable: $backend" >&2
        exit 1
    fi
    scan_file "$backend"
fi
find "$app_bundle/Contents" -type f -print | while IFS= read -r candidate; do
    scan_file "$candidate"
done

if ! otool -L "$executable" | grep -Eq '@(rpath|loader_path/\.\./Frameworks|executable_path/\.\./Frameworks)/QtCore\.framework/Versions/A/QtCore' \
    || ! otool -L "$executable" | grep -Eq '@(rpath|loader_path/\.\./Frameworks|executable_path/\.\./Frameworks)/QtNetwork\.framework/Versions/A/QtNetwork'; then
    echo "error: Prism executable does not reference bundled Qt frameworks" >&2
    exit 1
fi

if [ -x "$backend" ]; then
    if ! otool -L "$backend" | grep -Eq '@(rpath|loader_path/\.\./Frameworks|executable_path/\.\./Frameworks)/QtCore\.framework/Versions/A/QtCore' \
        || ! otool -L "$backend" | grep -Eq '@(rpath|loader_path/\.\./Frameworks|executable_path/\.\./Frameworks)/QtNetwork\.framework/Versions/A/QtNetwork'; then
        echo "error: Prism backend helper does not reference bundled Qt frameworks" >&2
        exit 1
    fi
    if [ ! -f "$app_bundle/Contents/Resources/jars/NewLaunch.jar" ]; then
        echo "error: Prism backend helper is missing NewLaunch.jar" >&2
        exit 1
    fi
    if [ -d "$app_bundle/Contents/MacOS/jars" ]; then
        echo "error: Prism backend JARs must not be placed in the nested-code directory Contents/MacOS" >&2
        exit 1
    fi
    if [ ! -f "$app_bundle/Contents/PlugIns/platforms/libqcocoa.dylib" ]; then
        echo "error: Prism backend helper is missing the Cocoa platform plugin" >&2
        exit 1
    fi
fi

echo "Qt runtime closure verified: $app_bundle"
