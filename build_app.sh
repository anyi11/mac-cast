#!/bin/bash
set -e

if [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

echo "=== Compiling Swift frontend ==="
SDK_PATH=$(xcrun --show-sdk-path -sdk macosx)
swiftc -parse-as-library -O -sdk "$SDK_PATH" -target arm64-apple-macosx13.0 MacastApp.swift -o MacastUI

if [ ! -f bin/MacOS/mpv ]; then
    echo "=== mpv binary not found, downloading... ==="
    mkdir -p bin/MacOS
    curl -L -o mpv-latest.tar.gz https://laboratory.stolendata.net/~djinn/mpv_osx/mpv-arm64-latest.tar.gz
    tar -C bin/MacOS --strip-components 4 -xzvf mpv-latest.tar.gz "*/mpv.app/Contents/MacOS"
    rm -f mpv-latest.tar.gz
fi

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

echo "=== Installing Python dependencies inside the App Bundle ==="
mkdir -p Macast.app/Contents/Resources/site-packages
/usr/bin/python3 -m ensurepip --default-pip || true
/usr/bin/python3 -m pip install --target Macast.app/Contents/Resources/site-packages -r requirements/darwin.txt

echo "=== Cleaning up unneeded Python packages ==="
rm -rf Macast.app/Contents/Resources/site-packages/{rich,pygments,typer,typer_slim,markdown_it,mdurl,shellingham,annotated_doc,setuptools}
rm -rf Macast.app/Contents/Resources/site-packages/*.dist-info
rm -f Macast.app/Contents/Resources/site-packages/lxml/objectify*.so
rm -rf Macast.app/Contents/Resources/site-packages/lxml/{html,includes,isoschematron}
find Macast.app/Contents/Resources/site-packages/lxml -name "*.pyx" -delete
find Macast.app/Contents/Resources/site-packages/lxml -name "*.pxi" -delete
find Macast.app/Contents/Resources/site-packages/lxml -name "*.h" -delete
rm -rf Macast.app/Contents/Resources/site-packages/cherrypy/test
rm -rf Macast.app/Contents/Resources/site-packages/cheroot/test

echo "=== Thinning and stripping Python extension binaries ==="
HOST_ARCH=$(uname -m)
find Macast.app/Contents/Resources/site-packages -type f -name "*.so" | while read -r file; do
    if lipo -info "$file" 2>/dev/null | grep -q "Architectures in the fat file"; then
        if lipo -info "$file" 2>/dev/null | grep -q "$HOST_ARCH"; then
            lipo -thin "$HOST_ARCH" "$file" -output "$file.tmp"
            mv "$file.tmp" "$file"
        fi
    fi
    strip -x "$file" 2>/dev/null || true
done

echo "=== Removing stale/invalid signatures ==="
find Macast.app -type f | while read -r file; do
    if file "$file" | grep -q "Mach-O"; then
        codesign --remove-signature "$file" 2>/dev/null || true
    fi
done

echo "=== Signing nested binaries manually ==="
find Macast.app -type f | while read -r file; do
    if file "$file" | grep -q "Mach-O"; then
        codesign --force --sign - "$file" 2>/dev/null || true
    fi
done

echo "=== Signing App Bundle ==="
codesign --force --deep --sign - Macast.app

echo "=== Build Completed successfully: Macast.app ==="
