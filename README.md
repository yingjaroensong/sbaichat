# SBAI Chat (Android)

Backend: https://sbaichat.com/api/index.php (PHP + MySQL)

## Build APK บน GitHub (ไม่ต้องติดตั้งอะไรในเครื่อง)
1. สมัคร/ล็อกอิน https://github.com แล้วกด **New repository** ตั้งชื่อ `sbaichat` (Private ได้)
2. กด **uploading an existing file** แล้วลากไฟล์และโฟลเดอร์ทั้งหมดในโฟลเดอร์นี้ขึ้นไป (รวม `.github`) แล้วกด Commit
3. ไปที่แท็บ **Actions** รอ "Build APK" เสร็จ (~8-12 นาที)
4. กดเข้า run ล่าสุด → ดาวน์โหลด **sbaichat-apk** (เป็น zip ข้างในมี app-release.apk)
5. อัปโหลด APK ไปที่ `public_html/download/sbaichat.apk` บนโฮสต์ → ผู้ใช้โหลดได้ที่ https://sbaichat.com/download/
