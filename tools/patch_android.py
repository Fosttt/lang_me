#!/usr/bin/env python3
"""Patch the CI-generated Android project for lang_me.

The android/ folder is not committed — CI runs `flutter create` and then this
script adds what the plugins need:
- INTERNET permission (AI server) and RECORD_AUDIO (speech_to_text);
- <queries> for the speech recognition and TTS services (Android 11+);
- release signing with the persistent keystore, if android/key.properties
  exists (CI writes it from secrets). Without it the debug key is kept —
  but then every build has a fresh signature and Android refuses to update
  the installed app in place.
"""

import re
import sys
from pathlib import Path

MANIFEST = Path("app/android/app/src/main/AndroidManifest.xml")
GRADLE_KTS = Path("app/android/app/build.gradle.kts")
GRADLE_GROOVY = Path("app/android/app/build.gradle")
KEY_PROPS = Path("app/android/key.properties")

PERMISSIONS = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
"""

QUERIES = """    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE"/>
        </intent>
    </queries>
"""


# `java.util.*` нельзя писать полным именем внутри android {} — имя `java`
# перекрыто Gradle-расширением, поэтому импорты добавляются в начало файла
KTS_IMPORTS = "import java.io.FileInputStream\nimport java.util.Properties\n"

SIGNING_KTS = """
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
"""

SIGNING_GROOVY = """
    def keystoreProperties = new Properties()
    def keystorePropertiesFile = rootProject.file('key.properties')
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
    }
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }
"""


def patch_signing() -> None:
    if not KEY_PROPS.exists():
        print("key.properties absent — keeping debug signing")
        return
    if GRADLE_KTS.exists():
        path, block = GRADLE_KTS, SIGNING_KTS
        debug_ref = 'signingConfig = signingConfigs.getByName("debug")'
        release_ref = 'signingConfig = signingConfigs.getByName("release")'
    elif GRADLE_GROOVY.exists():
        path, block = GRADLE_GROOVY, SIGNING_GROOVY
        debug_ref = "signingConfig signingConfigs.debug"
        release_ref = "signingConfig signingConfigs.release"
    else:
        print("no build.gradle(.kts) found", file=sys.stderr)
        sys.exit(1)

    text = path.read_text()
    if "key.properties" not in text:
        if path is GRADLE_KTS:
            text = KTS_IMPORTS + text
        # signingConfigs must live inside android {} before buildTypes
        idx = text.find("buildTypes")
        if idx < 0:
            print("buildTypes block not found", file=sys.stderr)
            sys.exit(1)
        line_start = text.rfind("\n", 0, idx) + 1
        text = text[:line_start] + block + "\n" + text[line_start:]
        text = text.replace(debug_ref, release_ref)
        path.write_text(text)
    print(f"{path} patched: release signing enabled")


def main() -> int:
    if not MANIFEST.exists():
        print(f"manifest not found: {MANIFEST}", file=sys.stderr)
        return 1
    text = MANIFEST.read_text()

    if "RECORD_AUDIO" not in text:
        text = re.sub(r"(<manifest[^>]*>\n)", r"\1" + PERMISSIONS, text, count=1)
    if "RecognitionService" not in text:
        # queries must be a direct child of <manifest>, before <application>
        text = text.replace("    <application", QUERIES + "    <application", 1)

    MANIFEST.write_text(text)
    print("AndroidManifest.xml patched")
    patch_signing()
    return 0


if __name__ == "__main__":
    sys.exit(main())
