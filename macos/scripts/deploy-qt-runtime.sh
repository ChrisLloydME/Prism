#!/bin/sh

set -eu

if [ "${PLATFORM_NAME:-macosx}" != "macosx" ]; then
    exit 0
fi

app_bundle="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
deploy_tool="${PRISM_MACDEPLOYQT:-/opt/homebrew/opt/qtbase/bin/macdeployqt}"

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

common_arguments="-no-plugins -no-strip -always-overwrite"
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
