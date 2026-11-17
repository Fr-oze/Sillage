#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if ! xcode-select -p >/dev/null 2>&1; then
    echo 'Les outils Apple manquent. Lancez xcode-select --install puis réessayez.' >&2
    exit 1
fi

case "${1:-}" in
    ''|--install) ;;
    *) echo 'Usage : ./build.sh [--install]' >&2; exit 1 ;;
esac

if swift build -c release --arch arm64; then
    BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
else
    echo 'Swift Package Manager indisponible : compilation directe avec swiftc.' >&2
    BIN_DIR="$PWD/.build/direct-release"
    mkdir -p "$BIN_DIR"
    SDK_PATH="${NEIGE_SDK_PATH:-$(xcrun --show-sdk-path)}"
    # Les outils de ce Mac ont un SDK 27 plus récent que le compilateur.
    # Le SDK 15.4 déjà présent permet de compiler sans modifier le système.
    if [[ -z "${NEIGE_SDK_PATH:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
        SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
    fi
    xcrun swiftc -O -target arm64-apple-macosx14.0 \
        -sdk "$SDK_PATH" \
        -module-cache-path "$PWD/.build/ModuleCache" \
        Sources/Neige/*.swift -o "$BIN_DIR/Neige"
fi
APP="$PWD/dist/Sillage.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Neige" "$APP/Contents/MacOS/Sillage"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Application prête : $APP"

if [[ "${1:-}" == '--install' ]]; then
    DEST="$HOME/Applications/Sillage.app"
    if [[ -e "$DEST" ]]; then
        echo "Une app existe déjà dans $DEST. Aucun remplacement effectué." >&2
        exit 1
    fi
    mkdir -p "$HOME/Applications"
    ditto "$APP" "$DEST"
    echo "Application installée : $DEST"
fi
