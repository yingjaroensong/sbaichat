import re, pathlib
m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
x = m.read_text()
perms = ['INTERNET','CAMERA','RECORD_AUDIO','MODIFY_AUDIO_SETTINGS','ACCESS_NETWORK_STATE','CHANGE_NETWORK_STATE',
         'BLUETOOTH','BLUETOOTH_CONNECT','WAKE_LOCK','READ_MEDIA_IMAGES','POST_NOTIFICATIONS',
         'FOREGROUND_SERVICE','FOREGROUND_SERVICE_DATA_SYNC','RECEIVE_BOOT_COMPLETED','USE_FULL_SCREEN_INTENT','VIBRATE','REQUEST_INSTALL_PACKAGES']
add = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in perms if p not in x)
add += '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
x = x.replace('<application', add + '    <application', 1)
x = re.sub(r'android:label="[^"]*"', 'android:label="SBAI Chat"', x, count=1)
if 'xmlns:tools' not in x:
    x = x.replace('xmlns:android="http://schemas.android.com/apk/res/android"',
                  'xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools"', 1)
svc = ('        <service android:name="id.flutter.flutter_background_service.BackgroundService"\n'
       '            android:foregroundServiceType="dataSync" android:exported="false"\n'
       '            tools:replace="android:exported" />\n')
if 'BackgroundService' not in x:
    x = x.replace('</application>', svc + '    </application>', 1)
m.write_text(x)
# minSdk 23 for flutter_webrtc
for g in ['android/app/build.gradle', 'android/app/build.gradle.kts']:
    p = pathlib.Path(g)
    if p.exists():
        s = p.read_text()
        s = re.sub(r'compileSdk(Version)?\s*=?\s*flutter\.compileSdkVersion', lambda mm: ('compileSdk = 35' if g.endswith('kts') else 'compileSdk 35'), s)
        s = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', lambda mm: ('minSdk = 23' if g.endswith('kts') else 'minSdkVersion 23'), s)
        if g.endswith('kts'):
            if 'isCoreLibraryDesugaringEnabled' not in s:
                s = s.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
                s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")\n}\n'
        else:
            if 'coreLibraryDesugaringEnabled' not in s:
                s = s.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
                s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'\n}\n"
        p.write_text(s)
# app icon
import shutil
for d in ['mdpi','hdpi','xhdpi','xxhdpi','xxxhdpi']:
    src = pathlib.Path(f'assets/icons/{d}.png')
    dst = pathlib.Path(f'android/app/src/main/res/mipmap-{d}/ic_launcher.png')
    if src.exists() and dst.parent.exists():
        shutil.copyfile(src, dst)

# ---- release signing from android/key.properties (created by CI) ----
G_PROPS = """
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) { keystoreProperties.load(new FileInputStream(keystorePropertiesFile)) }
"""
G_SIGN = """    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }
"""
K_PROPS = """
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) { keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile)) }
"""
K_SIGN = """    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
"""
for g in ['android/app/build.gradle', 'android/app/build.gradle.kts']:
    p = pathlib.Path(g)
    if not p.exists() or 'keystorePropertiesFile' in p.read_text():
        continue
    s = p.read_text()
    kts = g.endswith('kts')
    s = s.replace('\nandroid {', (K_PROPS if kts else G_PROPS) + '\nandroid {', 1)
    s = s.replace('    buildTypes {', (K_SIGN if kts else G_SIGN) + '    buildTypes {', 1)
    if kts:
        s = s.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")')
    else:
        s = re.sub(r'signingConfig\s*=?\s*signingConfigs\.debug',
                   'signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug', s)
    p.write_text(s)
    print('signing patched', g)

print('patched')
