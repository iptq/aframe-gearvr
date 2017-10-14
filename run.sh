#!/bin/bash
# Exit if any errors occur.
set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <project-folder> <osig-file>"
    exit
fi

PROJECT_FOLDER="$(pwd)/$1"
OSIG_FILE="$(pwd)/$2"
APKTOOL="$(pwd)/apktool/apktool"

# Debug printing.
function debug {
    if [[ -z "$DEBUG" ]]; then
        true
    else
        echo -e $@
    fi
}

# Random string generator.
function randomstring {
    cat /dev/urandom 2> /dev/null | base32 2> /dev/null | head -c ${1:-16}
}

# Variables
WORKDIR=$(mktemp)
KEYSTORE_PASSWORD=$(randomstring)
KEY_PASSWORD=$(randomstring)
debug "keystore password is $KEYSTORE_PASSWORD"

rm -rf $WORKDIR
mkdir -p $WORKDIR

# Generate keystore.
# Sorry, I was too lazy to handle metadata.
printf "$KEYSTORE_PASSWORD\x0a$KEYSTORE_PASSWORD\x0a\x0a\x0a\x0a\x0a\x0a\x0ayes" \
    | keytool -genkey -v -keystore $WORKDIR/.keystore -alias cordova -keypass $KEY_PASSWORD -keyalg RSA -keysize 2048 -validity 1

# Create boilerplate.
debug "workdir is $WORKDIR"
cordova create $WORKDIR/app
cd $WORKDIR/app

# Copy application.
rm -rf $WORKDIR/app/www
cp -r $PROJECT_FOLDER $WORKDIR/app/www

# Build the application.
cordova platform add android
cordova build android -- --keystore $WORKDIR/.keystore --alias cordova --storePassword $KEYSTORE_PASSWORD --password $KEY_PASSWORD

# Inject oculussig file, technique adapted from https://github.com/rclankhorst/OsigInjector

# Unpack the APK.
$APKTOOL d -f -o $WORKDIR/intermediate $WORKDIR/app/platforms/android/build/outputs/apk/android-debug.apk

# Copy over the signature file.
cp $OSIG_FILE $WORKDIR/intermediate/assets

# Repack the APK.
$APKTOOL b -o $WORKDIR/unsigned.apk $WORKDIR/intermediate

# Sign the APK.
jarsigner -sigalg SHA1withRSA -digestalg SHA1 -keystore $WORKDIR/.keystore -keypass $KEY_PASSWORD -storepass $KEYSTORE_PASSWORD $WORKDIR/unsigned.apk cordova
zipalign -v 4 $WORKDIR/unsigned.apk $WORKDIR/final.apk

echo "Done! Your final *.apk is located at:"
echo "$WORKDIR/final.apk"

