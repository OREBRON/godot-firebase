# Godot Firebase

Godot 4.7.2 için modüler Firebase eklentisi. Firebase C++ SDK 13.13.0
(iOS'ta Firebase iOS SDK 12.19) kullanır. Oyun yalnızca
ihtiyaç duyduğu modülleri alır:

| Modül | Klasör | Native sınıf | İçerik |
|---|---|---|---|
| core (zorunlu) | `core/` | `FirebaseAppNative` | App başlatma, görev ve sonuç tipleri |
| auth | `auth/` | `FirebaseAuthNative` | Anonim, Game Center, Sign in with Apple, hesap bağlama, silme |
| firestore | `firestore/` | `FirebaseFirestoreNative` | Doküman okuma/yazma, sorgu, batch, dinleyici |
| storage | `storage/` | `FirebaseStorageNative` | Dosya yükleme/indirme (bayt), indirme URL'si, metadata, silme |
| database | `database/` | `FirebaseDatabaseNative` | Realtime Database okuma/yazma, push, dinleyici |
| functions | `functions/` | `FirebaseFunctionsNative` | Callable HTTPS fonksiyon çağrısı |

Durum: GDScript API ve mock testleri geçiyor. Beş modülün native kodu iOS
(device + simulator) ve Android (arm64-v8a) için derlenip link ediliyor.
Cihazlarda henüz denenmedi (bkz. [Doğrulanmamış noktalar](#doğrulanmamış-noktalar)).

## Oyuna ekleme

1. `tools/bootstrap.sh`, ardından modül seçerek derle:
   ```bash
   tools/build.sh --modules auth
   tools/build.sh --modules auth,firestore,storage
   tools/package.sh   # build/dist/godot-firebase-<modüller>.zip (tümü: godot-firebase.zip)
   ```
2. Paketi oyunun kök dizinine aç; yalnızca derlenen modüllerin klasörleri
   gelir. Elle kopyalarsan kullanmadığın modül klasörlerini sil. Native
   derleme ve klasörler aynı modül listesine sahip olmalı; seçilen liste
   `bin/modules.txt` içinde.
3. Proje ayarlarında eklentiyi aç. `Firebase` autoload'u eklenir.
4. Firebase konsolundan `GoogleService-Info.plist` indir, `res://` köküne koy
   (dosya adı birebir aynı kalmalı). iOS export ayarlarında:
   - `firebase/sign_in_with_apple` açıksa `entitlements/additional` içine
     `<key>com.apple.developer.applesignin</key><array><string>Default</string></array>`
   - `firebase/sign_in_with_game_center` açıksa `entitlements/game_center`
   - Minimum iOS 15.
5. `templates/firestore.rules` kurallarını Firebase projesine yükle.
6. Functions varsayılan bölgesi `us-central1`. Başka bölge için proje ayarı
   `firebase/functions/region` ekle.

### Android

Android SDK (platform 35), NDK, JDK ve Godot Android Gradle build template'i
gerekir. `ANDROID_HOME` SDK dizinine işaret etmeli. Kurulu NDK varsayılan
28.1.13356709 değilse `NDK_VERSION` ortam değişkenini ayarla. Firebase
konsolundan oyunun Android paket kimliğine ait `google-services.json` indir:

```bash
ANDROID_HOME="$HOME/Library/Android/sdk" NDK_VERSION=28.2.13676358 \
  tools/build.sh --platforms android,macos --modules auth,firestore \
  --google-services /path/to/google-services.json --android-package com.example.game
tools/package.sh
```

`--android-package`, Android export preset'inin paket kimliğiyle aynı olmalı;
uyuşmazlık build'i durdurur. JSON oyunun dosyasıdır, eklentiye eklenmez.
Build, Firebase'in JSON dönüştürücüsüyle kaynak XML'i ve seçili modüllerin
ProGuard kurallarını AAR'a koyar. Android export preset'inde **Use Gradle
Build** açılmalı, yalnızca **arm64-v8a** etkin olmalı; Gradle export eklentisi
AAR'ı ve Firebase Maven bağımlılıklarını ekler. Android'da anonim giriş ve
diğer çekirdek modüller derlenir; Apple / Game Center girişleri Android'da
desteklenmez. Play Games v2 SDK ile oyunda alınan tek kullanımlık server auth
code, `Firebase.auth.sign_in_with_play_games(code)` veya anonim hesabı korumak
için `Firebase.auth.link_with_play_games(code)` ile Firebase'e verilebilir.
Play Console'da oyun sunucusu için tanımlanan Web OAuth client ID kullanılmalı;
Play Games SDK'nın başlatılması, proje kimliği ve `requestServerSideAccess`
çağrısı oyunun Android entegrasyonuna aittir. Eklenti oyun kimliklerini veya
auth code'u saklamaz.

## Kullanım

```gdscript
var result: FirebaseResult = await Firebase.auth.sign_in_anonymously().wait()
if not result.ok:
	push_warning(result.error_message)
	return
var uid: String = result.value.uid

# Anonim ilerlemeyi kalıcı hesaba bağla; uid değişmez.
await Firebase.auth.link_with_apple().wait()

var path := "users/%s/saves/main" % uid
await Firebase.firestore.set_doc(path, {"level": 3, "updated_at": FirebaseValue.server_timestamp()}, true).wait()
var snapshot: Dictionary = (await Firebase.firestore.get_doc(path).wait()).value
if snapshot.exists:
	print(snapshot.data.level)

var top: FirebaseResult = await Firebase.firestore.query("scores", [["score", ">=", 100]], [["score", "desc"]], 10).wait()
var id: int = Firebase.firestore.listen_doc(path, func(r: FirebaseResult): print(r.value.data))
Firebase.firestore.remove_listener(id)

var file := "users/%s/avatar.png" % uid
await Firebase.storage.upload_bytes(file, png_bytes, "image/png").wait()
var bytes: PackedByteArray = (await Firebase.storage.download_bytes(file).wait()).value

await Firebase.database.set_value("rooms/r1/players/%s" % uid, {"ready": true, "joined": FirebaseDatabase.SERVER_TIMESTAMP}).wait()
var key: String = (await Firebase.database.push_value("rooms/r1/chat", {"text": "selam"}).wait()).value
var room: int = Firebase.database.listen_value("rooms/r1", func(r: FirebaseResult): print(r.value.value))
Firebase.database.remove_listener(room)

var reward: FirebaseResult = await Firebase.functions.call_function("claimDailyReward", {"day": 3}).wait()
```

- Her istek `FirebaseTask` döner; `await task.wait()` bir `FirebaseResult`
  verir: `ok`, `value`, `error_code`, `error_message`. Negatif kodlar
  eklentiden gelir (`FirebaseResult.ERR_*`), pozitifler Firebase'den.
- Firestore özel değerleri: `FirebaseValue.timestamp()`, `server_timestamp()`,
  `increment()`, `delete_field()`. Zaman damgaları okunurken
  `{__firebase__ = "timestamp", seconds, nanos}` sözlüğü olarak gelir.
  Zaman damgası 0001-01-01 ile 9999-12-31 arasında olmalı. `server_timestamp()`,
  `increment()` ve `delete_field()` dizi içinde ve sorgu değerinde kullanılamaz.
- Firestore sorgu alanları ve `update_doc()` anahtarları noktalı alan yoludur
  (`"profile.level"`): boş parça ve `~ * / [ ]` içeremez. `limit` en fazla
  2147483647; `limit <= 0` limitsiz demek.
- Firestore tipleri: null, bool, int, float, String, PackedByteArray, Array
  (iç içe dizi yok), Dictionary (String anahtarlı).
- Database ve Functions tipleri: null, bool, int, float, String, Array
  (packed diziler dahil), Dictionary (String anahtarlı). Database anahtarları
  `. # $ [ ] /` içeremez; `FirebaseDatabase.SERVER_TIMESTAMP` sunucu zamanını
  Unix milisaniye olarak yazar.
- Storage metadata sonucu `{path, name, size, content_type, updated}`;
  `updated` Unix milisaniye. `download_bytes` varsayılan olarak en fazla 10 MB okur.
- Geçersiz veri native katmana ulaşmadan `ERR_INVALID_ARGUMENT` ile döner.
- Silinen modülün özelliği `null` olur (`Firebase.firestore == null`). Bu yüzden
  modül özellikleri (`Firebase.auth`, `Firebase.storage`, ...) tipsizdir;
  sonuçları tipli değişkene ata (`var r: FirebaseResult = await ...`) ya da
  `var auth: FirebaseAuth = Firebase.auth`.
- Editörde ve masaüstünde bellek içi mock çalışır (`Firebase.is_mock("auth")`);
  macOS kütüphanesi Firebase içermeyen bir editör stub'ıdır. Mobilde native
  başlatılamazsa mock'a düşülmez; istekler `ERR_UNAVAILABLE` döner.
- Hesap açtıran oyunlar App Store kuralı gereği hesap silme sunmalıdır:
  `Firebase.auth.delete_account()`.

## Geliştirme

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/run_tests.sh
```

Testler mock'larla çalışır. Native kod yalnızca iOS ve Android için
Firebase ile derlenir; gerçek davranış cihazda denenir.

### CI (self-hosted runner)

`.github/workflows/build.yml` `[self-hosted, macOS, ARM64]` runner'da çalışır
(Xcode, `godot` 4.7.2 ve `uv` gerekir). SDK indirmeleri runner'da
`../godot-firebase-third-party` altında kalıcı tutulur; ilk çalışma ~2.2 GB
indirir. Her çalışma mock testlerini koşar, sonra her varyantı (varsayılan:
beş modülün tümü, ardından her modül tek başına) macOS stub + iOS için
derler, testleri stub kütüphane yüklüyken tekrar koşar ve paketler:
`godot-firebase.zip` (tüm modüller) ve `godot-firebase-<modül>.zip`. `v*`
tag push'unda paketler ve `SHA256SUMS.txt` o tag'in GitHub release'ine
eklenir; branch ve PR çalışmaları paket yüklemez. Elle
başlatılan çalışmada `variants` girdisi başka modül listeleri seçer
(ör. `auth auth,storage`). Paket oyunun kök dizinine açılır.

Bağımlılık sürümleri `tools/versions.env` içindedir. godot-cpp'nin 4.7 tag'i
olmadığı için `master` bir commit'e sabitlenir ve `api_version=4.7` ile derlenir.

## Doğrulanmamış noktalar

Derleme doğrulandı: SDK zip yapısı, xcframework slice adları, çekirdek
framework listesi, Swift ve `-ObjC` bağlama bayrakları. Cihaz denemesinde
kontrol edilecekler:

- Godot iOS export'unun dinamik xcframework'ü gömmesi ve `*.bundle`
  kaynaklarını `add_apple_embedded_platform_bundle_file` ile kopyalaması.
- Çalışma zamanı: Objective-C kategorileri ve Swift kütüphanelerinin yüklenmesi.
- Uygulama boyutuna etkisi. Beş modüllü iOS kütüphanesi release'te ~20 MB
  (arm64, strip edilmemiş); modül başına ölçüm henüz yapılmadı.
- Android: JNI, AAR, bağımlılıklar ve arm64-v8a build'i eklendi; Android
  cihazda export, Firebase başlatma ve modül istekleri henüz doğrulanmadı.
