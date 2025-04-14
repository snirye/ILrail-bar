#!/bin/bash

BASE_DIR=/Users/danny/devel/playground/ILrail-bar
DMG_TEMP_DIR=$(mktemp -d -t ilrail)
APP_NAME="ILrail-bar"

# Build the app
pushd ${BASE_DIR}
xcodebuild -project ${APP_NAME}.xcodeproj -configuration Release

# Copy app to temporary folder
cp -R ${BASE_DIR}/build/Release/${APP_NAME}.app ${DMG_TEMP_DIR}

# Create a README file with instructions
cat > ${DMG_TEMP_DIR}/README.txt << EOL
# How to Install ILrail-bar

Since this app isn't signed with an Apple Developer certificate, macOS may show a security warning when you first try to open it.

To open the app:
1. Copy the ILrail-bar app to your Applications folder
2. Right-click (or Control-click) on the app icon
3. Select "Open" from the context menu
4. Click "Open" in the dialog box that appears

You only need to do this once. After the first launch, you can open the app normally.

EOL

# Self-sign the app with an ad-hoc signature
echo "Self-signing the app..."
codesign --verbose=4 --force --deep --sign - ${DMG_TEMP_DIR}/${APP_NAME}.app

# Create the DMG
hdiutil create -volname "${APP_NAME}" -srcfolder ${DMG_TEMP_DIR} -ov -format UDZO ${BASE_DIR}/${APP_NAME}.dmg

# Return to the original directory, suppressing output
popd > /dev/null 2>&1

# Clean up
echo "Cleaning up temp-dir..."
rm -rf ${DMG_TEMP_DIR}