import re, pathlib
m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
x = m.read_text()
perms = ['INTERNET','CAMERA','RECORD_AUDIO','MODIFY_AUDIO_SETTINGS','ACCESS_NETWORK_STATE','CHANGE_NETWORK_STATE',
         'BLUETOOTH','BLUETOOTH_CONNECT','WAKE_LOCK','READ_MEDIA_IMAGES','POST_NOTIFICATIONS']
add = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in perms if p not in x)
add += '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
x = x.replace('<application', add + '    <application', 1)
x = re.sub(r'android:label="[^"]*"', 'android:label="SBAI Chat"', x, count=1)
m.write_text(x)
# minSdk 23 for flutter_webrtc
for g in ['android/app/build.gradle', 'android/app/build.gradle.kts']:
    p = pathlib.Path(g)
    if p.exists():
        s = p.read_text()
        s = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', lambda mm: ('minSdk = 23' if g.endswith('kts') else 'minSdkVersion 23'), s)
        p.write_text(s)
# app icon
import shutil
for d in ['mdpi','hdpi','xhdpi','xxhdpi','xxxhdpi']:
    src = pathlib.Path(f'assets/icons/{d}.png')
    dst = pathlib.Path(f'android/app/src/main/res/mipmap-{d}/ic_launcher.png')
    if src.exists() and dst.parent.exists():
        shutil.copyfile(src, dst)
print('patched')
