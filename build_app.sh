#!/bin/bash
set -e

echo "=== Compiling Swift frontend ==="
SDK_PATH=$(xcrun --show-sdk-path -sdk macosx)
swiftc -parse-as-library -O -sdk "$SDK_PATH" -target arm64-apple-macosx13.0 MacastApp.swift -o MacastUI

echo "=== Creating App Bundle ==="
rm -rf Macast.app
mkdir -p Macast.app/Contents/MacOS
mkdir -p Macast.app/Contents/Resources

mv MacastUI Macast.app/Contents/MacOS/
cp Info.plist Macast.app/Contents/Info.plist

echo "=== Copying resources ==="
cp Macast.py Macast.app/Contents/Resources/
cp -R macast Macast.app/Contents/Resources/
cp -R macast_renderer Macast.app/Contents/Resources/
cp -R bin Macast.app/Contents/Resources/
cp -R i18n Macast.app/Contents/Resources/
cp -R requirements Macast.app/Contents/Resources/

echo "=== Signing App Bundle ==="
codesign --force --deep --sign - Macast.app

echo "=== Build Completed successfully: Macast.app ==="
