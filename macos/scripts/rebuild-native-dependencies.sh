#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repository_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
deployment_target="14.0"
qt_version="6.11.1"
qt_release_series="6.11"
qtbase_sha256="d9594a31228aa23ad6b531719a29b45f0f3989fe6c136d45767ea179f233c1ac"
network_auth_sha256="9f1d5bf22ccc033e42076186b964f9d4d4179fd0312a2c0f1aa19db42516563d"
qtbase_name="qtbase-everywhere-src-$qt_version"
network_auth_name="qtnetworkauth-everywhere-src-$qt_version"
download_root="$repository_root/.deps/downloads"
qt_prefix="$repository_root/.deps/qt-macos14"
qtbase_archive="$download_root/$qtbase_name.tar.xz"
network_auth_archive="$download_root/$network_auth_name.tar.xz"
backend_build_root="$repository_root/build-native"
frontend_build_root="$repository_root/.deriveddata-prism-native-backend"
vcpkg_root="${VCPKG_ROOT:-$repository_root/.deps/vcpkg}"
cmake_tool="${PRISM_CMAKE:-/opt/homebrew/bin/cmake}"
ninja_tool="${PRISM_NINJA:-/opt/homebrew/bin/ninja}"

for tool in "$cmake_tool" "$ninja_tool"; do
    if [ ! -x "$tool" ]; then
        echo "error: Required build tool is unavailable: $tool" >&2
        exit 1
    fi
done
if [ ! -f "$vcpkg_root/scripts/buildsystems/vcpkg.cmake" ]; then
    echo "error: vcpkg toolchain is unavailable: $vcpkg_root" >&2
    exit 1
fi

download_and_verify() {
    url="$1"
    archive="$2"
    expected_sha256="$3"

    if [ ! -f "$archive" ]; then
        /usr/bin/curl --fail --location "$url" --output "$archive"
    fi
    actual_sha256="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
    if [ "$actual_sha256" != "$expected_sha256" ]; then
        echo "error: Source checksum mismatch: $archive" >&2
        exit 1
    fi
}

mkdir -p "$download_root"
download_and_verify \
    "https://download.qt.io/official_releases/qt/$qt_release_series/$qt_version/submodules/$qtbase_name.tar.xz" \
    "$qtbase_archive" "$qtbase_sha256"
download_and_verify \
    "https://download.qt.io/official_releases/qt/$qt_release_series/$qt_version/submodules/$network_auth_name.tar.xz" \
    "$network_auth_archive" "$network_auth_sha256"

temporary_root="$(/usr/bin/mktemp -d /private/tmp/prism-qt-macos14.XXXXXX)"
trap '/bin/rm -rf "$temporary_root"' EXIT HUP INT TERM
qtbase_source="$temporary_root/$qtbase_name"
qtbase_build="$temporary_root/qtbase-build"
network_auth_source="$temporary_root/$network_auth_name"
network_auth_build="$temporary_root/qtnetworkauth-build"
mkdir -p "$qtbase_source" "$network_auth_source"
/usr/bin/tar -xf "$qtbase_archive" -C "$qtbase_source" --strip-components=1
/usr/bin/tar -xf "$network_auth_archive" -C "$network_auth_source" --strip-components=1

# These are generated, repository-local products. Removing every object cache
# prevents a host-OS object from surviving a deployment-target change.
/bin/rm -rf "$qt_prefix"
/bin/rm -rf "$backend_build_root"
/bin/rm -rf "$frontend_build_root"
/bin/rm -rf "$vcpkg_root/buildtrees" "$vcpkg_root/packages"

# Build QtBase itself so the app does not inherit a newer deployment target or
# transitive Homebrew dylibs from a prebuilt package. Bundled codecs/text libs
# keep the runtime closure self-contained; SecureTransport supplies TLS.
(
    cd "$qtbase_source"
    MACOSX_DEPLOYMENT_TARGET="$deployment_target" ./configure \
        -prefix "$qt_prefix" \
        -release \
        -framework \
        -nomake examples \
        -nomake tests \
        -no-dbus \
        -no-glib \
        -no-icu \
        -qt-pcre \
        -qt-zlib \
        -no-openssl \
        -securetransport \
        -no-cups \
        -qt-freetype \
        -qt-harfbuzz \
        -qt-libpng \
        -qt-libjpeg \
        -- \
        -B "$qtbase_build" \
        -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$ninja_tool" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        -DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON
)
MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" --build "$qtbase_build" --parallel 2
MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" --install "$qtbase_build"

MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" \
    -S "$network_auth_source" \
    -B "$network_auth_build" \
    -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$ninja_tool" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$qt_prefix" \
    -DCMAKE_PREFIX_PATH="$qt_prefix" \
    -DQt6_DIR="$qt_prefix/lib/cmake/Qt6" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
    -DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON \
    -DQT_BUILD_TESTS=OFF \
    -DQT_BUILD_EXAMPLES=OFF
MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" --build "$network_auth_build" --parallel 2
MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" --install "$network_auth_build"

VCPKG_BINARY_SOURCES=clear MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" \
    -S "$repository_root" \
    -B "$backend_build_root" \
    -G "Ninja Multi-Config" \
    -DCMAKE_MAKE_PROGRAM="$ninja_tool" \
    -DCMAKE_TOOLCHAIN_FILE="$vcpkg_root/scripts/buildsystems/vcpkg.cmake" \
    -DCMAKE_PREFIX_PATH="$qt_prefix" \
    -DQt6_DIR="$qt_prefix/lib/cmake/Qt6" \
    -DQt6NetworkAuth_DIR="$qt_prefix/lib/cmake/Qt6NetworkAuth" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
    -DVCPKG_TARGET_TRIPLET=arm64-osx

MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" --build "$backend_build_root" \
    --config Debug --target PrismBackend NewLaunch NewLaunchLegacy JavaCheck --parallel 2
MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" --build "$backend_build_root" \
    --config Release --target PrismBackend --parallel 2

MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" \
    -S "$repository_root/launcher/frontend" \
    -B "$frontend_build_root" \
    -G "Ninja Multi-Config" \
    -DCMAKE_MAKE_PROGRAM="$ninja_tool" \
    -DCMAKE_PREFIX_PATH="$qt_prefix;$backend_build_root/vcpkg_installed/arm64-osx" \
    -DQt6_DIR="$qt_prefix/lib/cmake/Qt6" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
    -DBUILD_TESTING=ON
MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" --build "$frontend_build_root" \
    --config Debug --target Launcher_frontend --parallel 2
MACOSX_DEPLOYMENT_TARGET="$deployment_target" "$cmake_tool" --build "$frontend_build_root" \
    --config Release --target Launcher_frontend --parallel 2

echo "Qt, vcpkg ports, and native backend rebuilt for macOS $deployment_target"
