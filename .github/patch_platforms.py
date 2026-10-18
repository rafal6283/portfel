#!/usr/bin/env python3
"""Uruchamiany raz po `flutter create`: nazwa, uprawnienia, stały klucz podpisu, Face ID."""
import glob, re, sys

def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in s:
            sys.exit(f'PATCH FAILED: {path}: nie znaleziono {old!r}')
        s = s.replace(old, new, 1)
    open(path, 'w', encoding='utf-8').write(s)
    print('patched', path)

# --- Android: podpis i id ---
g = 'android/app/build.gradle.kts'
s = open(g, encoding='utf-8').read()
s = re.sub(r'applicationId = "[^"]+"', 'applicationId = "pl.portfel.app"', s, count=1)
s = re.sub(r'minSdk = flutter\.minSdkVersion', 'minSdk = maxOf(flutter.minSdkVersion, 24)', s, count=1)
if 'signingConfigs.getByName("debug")' not in s or 'buildTypes {' not in s:
    sys.exit('PATCH FAILED: build.gradle.kts ma inny układ')
s = s.replace('    buildTypes {', '''    // Stały klucz w (prywatnym) repo – każda nowa wersja instaluje się jako aktualizacja.
    signingConfigs {
        create("portfel") {
            storeFile = file("../../.github/portfel.jks")
            storePassword = "portfel123"
            keyAlias = "portfel"
            keyPassword = "portfel123"
        }
    }

    buildTypes {''', 1)
s = s.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("portfel")')
open(g, 'w', encoding='utf-8').write(s)
print('patched', g)
# klucz zostaje w .github/ (android/.gitignore pomija *.jks)

m = 'android/app/src/main/AndroidManifest.xml'
s = open(m, encoding='utf-8').read()
s = re.sub(r'android:label="[^"]*"', 'android:label="Portfel"', s, count=1)
s = re.sub(r'(<manifest[^>]*>)', r'''\1
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>''', s, count=1)
open(m, 'w', encoding='utf-8').write(s)
print('patched', m)

acts = glob.glob('android/app/src/main/kotlin/**/MainActivity.kt', recursive=True)
if not acts:
    sys.exit('PATCH FAILED: brak MainActivity.kt')
for a in acts:
    s = open(a, encoding='utf-8').read()
    s = s.replace('io.flutter.embedding.android.FlutterActivity', 'io.flutter.embedding.android.FlutterFragmentActivity')
    s = re.sub(r':\s*FlutterActivity\(\)', ': FlutterFragmentActivity()', s)
    open(a, 'w', encoding='utf-8').write(s)
    print('patched', a)

# --- iOS ---
p = 'ios/Runner/Info.plist'
s = open(p, encoding='utf-8').read()
s = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)', r'\1Portfel\2', s, count=1)
s = re.sub(r'(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)', r'\1Portfel\2', s, count=1)
idx = s.rfind('</dict>')
s = s[:idx] + '\t<key>NSFaceIDUsageDescription</key>\n\t<string>Face ID chroni dostęp do Twojego portfela.</string>\n' + s[idx:]
open(p, 'w', encoding='utf-8').write(s)
print('patched', p)
