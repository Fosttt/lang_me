#!/usr/bin/env python3
"""Patch the CI-generated Android project for lang_me.

The android/ folder is not committed — CI runs `flutter create` and then this
script adds what the plugins need:
- INTERNET permission (AI server) and RECORD_AUDIO (speech_to_text);
- <queries> for the speech recognition and TTS services (Android 11+).
"""

import re
import sys
from pathlib import Path

MANIFEST = Path("app/android/app/src/main/AndroidManifest.xml")

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
    print("AndroidManifest.xml patched:")
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
