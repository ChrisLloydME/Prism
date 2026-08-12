#!/bin/sh

set -eu

if [ "${PLATFORM_NAME:-macosx}" != "macosx" ]; then
    exit 0
fi

app_bundle="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
deploy_tool="${PRISM_MACDEPLOYQT:-}"
if [ -z "$deploy_tool" ] && [ -n "${SRCROOT:-}" ]; then
    local_deploy_tool="$SRCROOT/../.deps/qt-macos14/bin/macdeployqt"
    if [ -x "$local_deploy_tool" ]; then
        deploy_tool="$local_deploy_tool"
    fi
fi
deploy_tool="${deploy_tool:-/opt/homebrew/opt/qtbase/bin/macdeployqt}"

case "$app_bundle" in
    "${TARGET_BUILD_DIR}/"*.app) ;;
    *)
        echo "error: Refusing to deploy Qt outside TARGET_BUILD_DIR: $app_bundle" >&2
        exit 1
        ;;
esac

if [ ! -d "$app_bundle/Contents/MacOS" ]; then
    echo "error: Prism application bundle is unavailable: $app_bundle" >&2
    exit 1
fi
if [ ! -x "$deploy_tool" ]; then
    echo "error: macdeployqt is unavailable: $deploy_tool" >&2
    exit 1
fi

backend_source="${PRISM_BACKEND_EXECUTABLE:-}"
if [ -z "$backend_source" ] && [ -n "${SRCROOT:-}" ]; then
    backend_build_root="$SRCROOT/../build-native"
    backend_source="$backend_build_root/${CONFIGURATION:-Debug}/prism_backend"
    cmake_tool="${PRISM_CMAKE:-}"
    if [ -z "$cmake_tool" ] && [ -f "$backend_build_root/CMakeCache.txt" ]; then
        cmake_tool="$(sed -n '/^CMAKE_COMMAND:INTERNAL=/{s///;p;q;}' "$backend_build_root/CMakeCache.txt")"
    fi
    if [ -z "$cmake_tool" ]; then
        cmake_tool="$(command -v cmake 2>/dev/null || true)"
    fi
    if [ -z "$cmake_tool" ]; then
        for candidate in /opt/homebrew/bin/cmake /usr/local/bin/cmake; do
            if [ -x "$candidate" ]; then
                cmake_tool="$candidate"
                break
            fi
        done
    fi
    if [ ! -x "$cmake_tool" ]; then
        echo "error: CMake is unavailable. Set PRISM_CMAKE or configure $backend_build_root first." >&2
        exit 1
    fi
    # Always ask the incremental build graph to refresh the helper. Merely
    # checking for an existing executable can silently package stale backend
    # code after a launcher source edit. Xcode launched from Finder does not
    # inherit Homebrew's PATH, so use the CMake recorded by this build tree.
    "$cmake_tool" --build "$backend_build_root" --config "${CONFIGURATION:-Debug}" \
        --target PrismBackend NewLaunch NewLaunchLegacy JavaCheck --parallel 2
fi

backend_destination="$app_bundle/Contents/MacOS/prism_backend"
if [ -n "$backend_source" ]; then
    if [ ! -x "$backend_source" ]; then
        echo "error: Native Prism backend helper is unavailable: $backend_source" >&2
        exit 1
    fi
    cp "$backend_source" "$backend_destination"
    chmod 755 "$backend_destination"

    backend_jars="$(dirname "$(dirname "$backend_source")")/jars"
    if [ ! -f "$backend_jars/NewLaunch.jar" ]; then
        echo "error: Native Prism backend launch jars are unavailable: $backend_jars" >&2
        exit 1
    fi
    # JARs are data consumed by the helper, not nested Mach-O code. Keeping
    # them under Contents/MacOS causes Xcode's final CodeSign phase to reject
    # each unsigned JAR as a malformed nested-code component.
    rm -rf "$app_bundle/Contents/MacOS/jars"
    mkdir -p "$app_bundle/Contents/Resources/jars"
    find "$backend_jars" -maxdepth 1 -type f -name '*.jar' -exec cp '{}' "$app_bundle/Contents/Resources/jars/" ';'

    sparkle_source="$(dirname "$(dirname "$backend_source")")/frameworks/Sparkle/Sparkle.framework"
    if [ -d "$sparkle_source" ]; then
        mkdir -p "$app_bundle/Contents/Frameworks"
        cp -R "$sparkle_source" "$app_bundle/Contents/Frameworks/"
    fi
fi

# The helper currently hosts the extracted legacy domain graph and therefore
# needs the Cocoa platform plugin in addition to its framework closure.
common_arguments="-no-strip -always-overwrite"
if [ -x "$backend_destination" ]; then
    common_arguments="$common_arguments -executable=$backend_destination"
fi
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
    "$deploy_tool" "$app_bundle" $common_arguments -no-codesign
else
    # Xcode uses '-' for its ad-hoc Debug identity. Passing that identity to
    # macdeployqt is required: preserving Homebrew's existing Qt signature
    # gives the nested framework a different Team ID and dyld aborts before
    # application startup under Hardened Runtime.
    signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    "$deploy_tool" "$app_bundle" $common_arguments "-codesign=${signing_identity}"
fi

if [ ! -f "$app_bundle/Contents/Frameworks/QtCore.framework/Versions/A/QtCore" ] \
    || [ ! -f "$app_bundle/Contents/Frameworks/QtNetwork.framework/Versions/A/QtNetwork" ]; then
    echo "error: macdeployqt did not produce the required Qt runtime closure" >&2
    exit 1
fi
