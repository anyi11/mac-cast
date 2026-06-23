#!/bin/bash
set -e

echo "=== Compiling Swift frontend ==="
SDK_PATH=$(xcrun --show-sdk-path -sdk macosx)
swiftc -parse-as-library -O -sdk "$SDK_PATH" -target arm64-apple-macosx13.0 MacastApp.swift -o MacastUI

if [ ! -f bin/MacOS/mpv ]; then
    echo "=== mpv binary not found, downloading... ==="
    mkdir -p bin/MacOS
    curl -L -o mpv-latest.tar.gz https://laboratory.stolendata.net/~djinn/mpv_osx/mpv-latest.tar.gz
    tar -C bin/MacOS --strip-components 3 -xzvf mpv-latest.tar.gz mpv.app/Contents/MacOS
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

echo "=== Signing App Bundle ==="
codesign --force --deep --sign - Macast.app

echo "=== Build Completed successfully: Macast.app ==="
