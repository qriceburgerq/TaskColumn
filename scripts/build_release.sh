#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASES_DIR="${ROOT_DIR}/releases"
APP_NAME="TaskColumn"
CACHE_DIR="${ROOT_DIR}/swift-cache"

# Determine version
ARG="${1:-}"

find_latest_version() {
    if [ ! -d "${RELEASES_DIR}" ]; then
        echo "1.0.0"
        return
    fi
    local latest=$(ls -1d "${RELEASES_DIR}"/v* 2>/dev/null | sed 's/.*\/v//' | sort -V | tail -n 1)
    if [ -z "$latest" ]; then
        echo "1.0.0"
    else
        echo "$latest"
    fi
}

bump_patch() {
    local ver="$1"
    local major=$(echo "$ver" | cut -d. -f1)
    local minor=$(echo "$ver" | cut -d. -f2)
    local patch=$(echo "$ver" | cut -d. -f3)
    patch=$((patch + 1))
    echo "${major}.${minor}.${patch}"
}

if [ "$ARG" = "bump" ]; then
    LATEST=$(find_latest_version)
    VERSION=$(bump_patch "$LATEST")
    echo "⚡ Auto-bumping version from ${LATEST} to ${VERSION}"
elif [ -n "$ARG" ]; then
    VERSION="${ARG#v}"
else
    LATEST=$(find_latest_version)
    VERSION="${LATEST}"
fi

TAG="v${VERSION}"
RELEASE_DIR="${RELEASES_DIR}/${TAG}"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"

echo "=========================================="
echo "🚀 Building ${APP_NAME} Release: ${TAG}"
echo "📁 Output Directory: ${RELEASE_DIR}"
echo "=========================================="

mkdir -p "${RELEASE_DIR}"
mkdir -p "${CACHE_DIR}"

# 1. Compile Swift sources into single native Mach-O executable
echo "🔨 Compiling Swift sources..."
swiftc -O \
    -module-cache-path "${CACHE_DIR}" \
    -parse-as-library \
    "${ROOT_DIR}/src/Models/TaskModels.swift" \
    "${ROOT_DIR}/src/Services/GoogleAuthService.swift" \
    "${ROOT_DIR}/src/Services/GoogleTasksAPIService.swift" \
    "${ROOT_DIR}/src/Services/DataManager.swift" \
    "${ROOT_DIR}/src/Services/HotkeyManager.swift" \
    "${ROOT_DIR}/src/Services/MenuBarController.swift" \
    "${ROOT_DIR}/src/Views/CalendarMonthView.swift" \
    "${ROOT_DIR}/src/Views/TaskDetailView.swift" \
    "${ROOT_DIR}/src/Views/QuickAddPanel.swift" \
    "${ROOT_DIR}/src/Views/SettingsView.swift" \
    "${ROOT_DIR}/src/Views/MainSplitView.swift" \
    "${ROOT_DIR}/src/App.swift" \
    -o "${RELEASE_DIR}/${APP_NAME}_bin"

echo "✅ Compilation successful!"

# 2. Assemble macOS App Bundle
echo "📦 Assembling ${APP_NAME}.app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

mv "${RELEASE_DIR}/${APP_NAME}_bin" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy AppIcon if available
if [ -f "${ROOT_DIR}/AppIcon.icns" ]; then
    cp "${ROOT_DIR}/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Generate Info.plist
cat << PLIST > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_TW</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.taskcolumn</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

# 3. Ad-hoc codesign for Apple Silicon execution
echo "🔏 Applying ad-hoc codesign..."
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

# Clean up swift cache
rm -rf "${CACHE_DIR}"

echo "=========================================="
echo "🎉 Build finished successfully!"
echo "📍 App Path: ${APP_BUNDLE}"
echo "📊 App Size: $(du -sh "${APP_BUNDLE}" | cut -f1)"
echo "=========================================="
