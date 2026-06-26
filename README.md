# 🌙 Noor Database — YouTube Auto-Sync

نظام مستقل لجلب الفيديوهات الجديدة من يوتيوب تلقائياً كل 3 ساعات، يعمل على GitHub Actions.

## ✨ المزايا

- ✅ **مجاني 100%** — GitHub Actions يوفر 2000 دقيقة/شهر مجاناً
- ✅ **كل 3 ساعات** — 8 مرات يومياً
- ✅ **لا حاجة لإعداد Token** — `GITHUB_TOKEN` مدمج تلقائياً
- ✅ **دمج بدلاً من الاستبدال** — لا حذف للفيديوهات القديمة
- ✅ **أرشفة تلقائية** — عند تجاوز 5000 فيديو، ينقل الأقدم لأرشيف
- ✅ **تصنيف ذكي** — بث مباشر / فيديوهات / شورتس
- ✅ **منع التكرار** — يعتمد على videoUrl كمفتاح فريد

---

## 🚀 الإعداد (3 خطوات فقط!)

### الخطوة 1: إنشاء المستودع

1. اذهب لـ: https://github.com/new
2. **Repository name**: `noor-database`
3. اختر **Public** أو **Private**
4. ✅ فعّل **"Add a README file"**
5. اضغط **"Create repository"**

### الخطوة 2: رفع الملفات

ارفع كل الملفات من هذا المجلد للمستودع:

```
noor-database/
├── .github/workflows/youtube-sync.yml
├── .gitignore
├── tools/youtube_sync_dart/
│   ├── bin/sync_youtube.dart
│   ├── lib/youtube_sync.dart
│   └── pubspec.yaml
└── radio_database/
    ├── index.json
    └── youtube_channels.json
```

**طريقة الرفع:**
- اسحب الملفات مباشرة على صفحة GitHub (Drag & Drop)
- أو استخدم git:
```bash
git clone https://github.com/YOUR_USERNAME/noor-database.git
# انسخ الملفات
git add .
git commit -m "Initial setup"
git push
```

### الخطوة 3: أضف قنواتك

عدّل ملف `radio_database/youtube_channels.json` وأضف قنواتك:

```json
{
  "version": 1,
  "channels": [
    {
      "categoryId": "zein_khair_allah",
      "channelId": "UCQKqsmz6fY_4l5ilNpJ5iSw",
      "channelName": "جديد الشيخ زين خير الله"
    },
    {
      "categoryId": "iyad_alqunibi",
      "channelId": "UCahYlNszeMy_PHffYvgAOHg",
      "channelName": "جديد الدكتور اياد القنيبي"
    }
  ]
}
```

#### كيف أجد الـ channelId؟
1. افتح قناة اليوتيوب
2. اضغط بالزر الأيمن على الصفحة → "View Page Source"
3. ابحث عن `channel_id` أو `externalId`
4. ستجده بصيغة `UCxxxxxxxxxxxxxxxxxxxxxxxx` (24 حرف)

أو استخدم: https://commentpicker.com/youtube-channel-id.php

---

## ⏰ الجدولة

النظام يعمل **كل 3 ساعات** تلقائياً:
- 00:00, 03:00, 06:00, 09:00, 12:00, 15:00, 18:00, 21:00 (UTC)

### لتغيير الفترة
عدّل السطر في `.github/workflows/youtube-sync.yml`:
```yaml
schedule:
  - cron: '0 */3 * * *'   # كل 3 ساعات (الحالي)
  # - cron: '0 * * * *'   # كل ساعة
  # - cron: '0 */6 * * *' # كل 6 ساعات
```

---

## 🧪 تشغيل يدوي (لاختبار النظام)

1. اذهب لتبويب **Actions** في المستودع
2. اختر **"Sync YouTube Videos"** من القائمة الجانبية
3. اضغط **"Run workflow"**
4. اختر فرع `main` واضغط **"Run workflow"**
5. انتظر 2-3 دقائق

---

## 📂 النتيجة المتوقعة

بعد أول مزامنة ناجحة، ستجد:

```
radio_database/
├── index.json                           ← محدّث بالملفات الجديدة
├── youtube_channels.json                ← قنواتك
├── zein_khair_allah/                    ← مجلد جديد لكل قناة
│   ├── zein_khair_allah.live.json       ← البثوث المباشرة
│   ├── zein_khair_allah.videos.json     ← الفيديوهات
│   └── zein_khair_allah.shorts.json     ← الشورتس
├── iyad_alqunibi/
│   ├── iyad_alqunibi.live.json
│   ├── iyad_alqunibi.videos.json
│   └── iyad_alqunibi.shorts.json
└── ...
```

### index.json
```json
{
  "files": [
    "zein_khair_allah/zein_khair_allah.live.json",
    "zein_khair_allah/zein_khair_allah.videos.json",
    "zein_khair_allah/zein_khair_allah.shorts.json",
    "iyad_alqunibi/iyad_alqunibi.live.json",
    ...
  ]
}
```

---

## 🔧 كيف يعمل النظام

```
كل 3 ساعات:
  1. GitHub Actions يشغل pipeline على ubuntu-latest
  2. يثبت Dart SDK
  3. سكربت Dart يقرأ youtube_channels.json
  4. لكل قناة:
     a. يجلب آخر 15 فيديو من YouTube RSS
     b. يجلب قوائم البث المباشر (UULV) والشورتس (UUSH)
     c. يجلب metadata عبر youtube_explode_dart
     d. يصنف كل فيديو: live / videos / shorts
     e. يدمج الجديد مع الموجود (لا حذف!)
     f. إذا تجاوز 5000 → ينقل الأقدم لأرشيف
     g. يكتب 3 ملفات: .live.json, .videos.json, .shorts.json
  5. يحدّث index.json
  6. git commit + push تلقائياً (بـ GITHUB_TOKEN المدمج)
```

---

## 📊 الاستهلاك

- **كل 3 ساعات** = 8 مرات يومياً = ~240 مرة/شهر
- **كل مزامنة** = ~2-3 دقائق
- **إجمالي شهري** = ~500-700 دقيقة
- **الحد المجاني** = 2000 دقيقة/شهر ✅ (كافٍ جداً)

---

## 🆘 حل المشاكل

### المشكلة: الـ workflow لا يعمل تلقائياً
GitHub قد يؤخر الـ scheduled workflows بـ 5-15 دقيقة في أوقات الذروة.
**الحل**: شغّله يدوياً من تبويب Actions.

### المشكلة: "No channels in manifest"
**السبب**: `youtube_channels.json` فارغ أو الـ channelId يحتوي `xxxxx`.
**الحل**: أضف قنواتك الحقيقية.

### المشكلة: "RSS fetch failed"
**السبب**: channelId غير صحيح أو يوتيوب حظر الـ IP مؤقتاً.
**الحل**: تأكد من صحة الـ channelId، أعد المحاولة لاحقاً.

### المشكلة: لا توجد تغييرات بعد المزامنة
**السبب**: لم تنشر القنوات فيديوهات جديدة منذ آخر مزامنة.
**الحل**: طبيعي — انتظر المزامنة التالية.

---

## 📝 ملاحظات

- **النظام منفصل تماماً** عن أي مستودع آخر
- **يمكن إضافة/حذف قنوات** بتعديل `youtube_channels.json` فقط
- **الحد المجاني**: 2000 دقيقة/شهر — استهلاكنا ~600 دقيقة فقط
- **يمكن تقليل الفترة** لـ كل ساعة إذا أردت (~1440 دقيقة/شهر — لا يزال مجانياً)
