#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 -module-name EditorCore Sources/EditorCore/*.swift \
  -emit-module -emit-library -emit-module-path .build/EditorCore.swiftmodule \
  -o .build/libEditorCore.dylib
swiftc -swift-version 5 -parse-as-library Sources/TextEditor/*.swift \
  -I .build -L .build -lEditorCore \
  -framework AppKit -framework SwiftUI -framework WebKit \
  -Xlinker -rpath -Xlinker @executable_path \
  -o .build/TextEditor
install_name_tool -id @rpath/libEditorCore.dylib .build/libEditorCore.dylib
install_name_tool -change .build/libEditorCore.dylib @rpath/libEditorCore.dylib .build/TextEditor
APP="dist/Text Editor.app"
rm -rf "$APP" "dist/文本编辑器.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/TextEditor "$APP/Contents/MacOS/TextEditor"
cp .build/libEditorCore.dylib "$APP/Contents/MacOS/libEditorCore.dylib"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
open "$APP"
