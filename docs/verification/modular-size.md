# Modüler paket boyut ölçümü (#56)

Tarih: 2026-09-30. Kaynak: `4091850` üzerindeki çalışma ağacı; üretim kaynakları değiştirilmedi.
Ölçüm yalnız mevcut `SConstruct modules=` seçimini kullanır. Geçici çıktılar
`build/probes/package-size/` ve `build/probes/fixture/` altındadır, depoya girmez.

## Ortam ve sabitler

| Girdi | Değer |
| --- | --- |
| Godot / export template | 4.7.2.stable.official.ed1daf0bf (resmi 4.7.2 `.tpz`, SHA-512 doğrulandı) |
| godot-cpp | `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5` |
| Firebase C++ / iOS SDK | 13.13.0 / 12.19.1 (`tools/versions.env`) |
| Android NDK | `~/Library/Android/sdk/ndk/28.2.13676358` (LLD 19.0.1), `--target=aarch64-linux-android24`, arm64-v8a |
| iOS | Xcode iPhoneOS27.0 SDK, `-miphoneos-version-min=15.0`, device arm64 |
| Gradle build | Godot 4.7.2 `android_source.zip`, compileSdk 36, minSdk 24, JDK 21 |
| Minification | Godot Gradle şablonunda R8/minify kapalı; üç Android varyantında aynı |
| Fixture | `build/probes/fixture/template`: aynı `project.godot`, `main.gd`, `icon.png`, sahte `GoogleService-Info.plist` ve `tests/fixtures/google-services.json` |

Her varyant ayrı fixture kökünde (`ios-auth`, `ios-full`, `android-a1..a3`) export edildi.
Oyun konfigürasyonu yalnız fixture'da bulunur; release ZIP'lerine girmez.

## Gerçek link komutları

Tam komutlar `build/probes/package-size/<variant>/<platform>/build.log` içindedir (`verbose=yes`).

- **Android:** `clang++ -shared --target=aarch64-linux-android24 -march=armv8-a -fvisibility=hidden -s -Wl,--no-undefined ... libgodot-cpp...a -lfirebase_<modüller> -lfirebase_app -llog`.
  Strip var (`-s`). Section GC yok: `--gc-sections` veya `-ffunction-sections` verilmiyor.
  Aynı komuta `-Wl,--gc-sections` eklenince kazanç yalnız 8,888 B (auth) ve 4,392 B (full); anlamlı değil.
- **iOS:** `clang++ ... -fvisibility=hidden -Wl,-S -Wl,-x -Wl,-dead_strip ... -ObjC -framework <Firebase iOS framework'leri> -lfirebase_<modüller> -lfirebase_app -lc++ -lz -lsqlite3`.
  `-dead_strip` var. `-ObjC` bütün ObjC sınıf/kategori objelerini tuttuğu için dead-strip Firebase iOS SDK'yı fazla küçültemez.
- Android `.so`, `NEEDED libc++_shared.so` içerir (`llvm-readelf -d`): mevcut build zaten paylaşılan STL kullanıyor; APK'da tek `libc++_shared.so` (1,374,336 B) var.

## Sonuçlar

Bayt değerleri tam sayıdır. Fark = full − auth.

### Native binary (stripped release)

| Platform | Auth | Full | Fark | Yüzde |
| --- | ---: | ---: | ---: | ---: |
| Android `.so` | 1,528,912 | 2,934,296 | 1,405,384 | +91.9% |
| Android `.so` deflate -9 | 464,283 | 833,175 | 368,892 | +79.5% |
| iOS `.dylib` | 4,283,552 | 20,084,144 | 15,800,592 | +368.9% |
| iOS `.dylib` deflate -9 | 1,223,105 | 6,891,762 | 5,668,657 | +463.5% |

Geri bildirimdeki "2.8 MB", ölçülen full Android `.so` ile uyumludur: 2,934,296 B = 2.80 MiB.

**Android full `.so` içeriği** (link map, `-Wl,-Map`): `firebase_app` 529,809 B, `firebase_firestore` 378,392 B,
godot-cpp 338,950 B, eklenti kaynakları 217,784 B, `firebase_auth` 146,950 B, `firebase_database` 130,397 B,
`firebase_storage` 83,908 B, `firebase_functions` 22,734 B. Android'de Firebase ürünlerinin asıl kodu Java/Maven
tarafındadır; C++ katmanı JNI sarmalayıcısıdır.

**iOS full `.dylib` içeriği** (link map, `-Wl,-map`; sembol toplamı 15,686,209 B): gRPC 5,128,433,
FirebaseFirestoreInternal 2,547,240, FirebaseAuth 1,166,938, `firebase_app` 1,017,203, openssl_grpc 1,017,181,
`firebase_firestore` 596,037, FirebaseFirestore 527,054, FirebaseDatabase 525,128, absl 470,263. Firestore zinciri
(gRPC, openssl_grpc, absl, leveldb, FirestoreInternal, FirebaseFirestore, C++ Firestore) yaklaşık 10.5 MB'tır.
iOS'ta Firebase iOS SDK'nın kendisi statik olarak bu dylib'e girer; farkın ana kaynağı budur.

### iOS uygulama ve IPA

`--export-release iOS` (export project only) + `xcodebuild -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO`.
**İmzalı IPA üretilmedi** (imza kimliği kullanılmadı). IPA satırı, `Payload/<app>` klasörünün `zip -9` arşividir;
App Store şifreleme ve thinning sonrası indirme boyutu değildir.

| Çıktı | Auth | Full | Fark | Yüzde |
| --- | ---: | ---: | ---: | ---: |
| Unpacked `.app` | 91,076,076 | 106,916,145 | 15,840,069 | +17.4% |
| İmzasız IPA (zip -9) | 25,630,398 | 31,338,442 | 5,708,044 | +22.3% |
| Resource bundle sayısı / disk | 9 / 72 KB | 16 / 128 KB | 7 / 56 KB | |

Godot motor binary'si her iki varyantta 86,649,248 B'tır.

### Android APK ve bağımlılık ayrıştırması

Gradle build ile üç release APK (debug keystore ile imzalı). `.so` ve `.dex` girdileri APK'da sıkıştırmasız saklanır;
"deflate -9" satırı her girdinin ayrı sıkıştırılmış toplamıdır (indirme boyutuna yaklaşım).

| Varyant | Native | Maven | APK | APK deflate -9 | dex |
| --- | --- | --- | ---: | ---: | ---: |
| a1 | auth | auth | 86,356,969 | 29,435,729 | 11,885,884 |
| a2 | full | auth | 87,762,353 | 29,804,621 | 11,885,884 |
| a3 | full | full | 95,751,422 | 32,862,366 | 19,615,488 |

| Karşılaştırma | APK farkı | Yüzde | Deflate farkı | Yüzde |
| --- | ---: | ---: | ---: | ---: |
| a2 − a1 (yalnız native) | 1,405,384 | +1.63% | 368,892 | +1.25% |
| a3 − a2 (yalnız Maven) | 7,989,069 | +9.10% | 3,057,745 | +10.26% |
| a3 − a1 (tam fark) | 9,394,453 | +10.88% | 3,426,637 | +11.64% |

Maven kapanışı (`./gradlew --offline :dependencies --configuration standardReleaseRuntimeClasspath`):
auth varyantı 84, full varyantı 125 benzersiz artifact. Full ile gelen 41 artifact arasında Firestore/Database/
Storage/Functions, `firebase-appcheck`, gRPC (`grpc-android/api/core/okhttp/protobuf-lite/stub/util`),
`protobuf-javalite`, OkHttp/Okio, `androidx.datastore` ailesi ve `libdatastore_shared_counter.so` bulunur.
Tam liste: `build/probes/package-size/maven-{auth,full}-set.txt`.

### a2 (full native + auth Maven) yükleme durumu

**Doğrulanmadı.** Android cihaz bağlı değil, AVD yok. Emulator imajı indirmesi diskte yer kalmadığı için
("No space left on device") başarısız oldu. Statik kanıt:

- a2 `.so` yalnız `liblog`, `libc++_shared`, `libm`, `libdl`, `libc` ister; `dlopen` için eksik DSO yok.
- JNI sınıf çözümlemesi çalışma zamanındadır. Firebase C++ modüllerinin static initializer ile
  `firebase::AppCallback` kaydı yaptığı import listesinde görülüyor (`AppCallback::AddCallback`); `App::Create`
  sırasında bu callback'lerin eksik Java ürününe dokunup dokunmadığı yalnız çalıştırarak görülebilir.

Bu nedenle a2 − a1 farkı **küçük universal için geçerli tasarruf örneği sayılmaz**. Kabul maddesi açık kalır.

### Sembol ve export gözlemleri

- Android full `.so` 5,480, auth `.so` 2,230 dinamik sembol export eder. `-fvisibility=hidden` yalnız eklenti ve
  godot-cpp kaynaklarına uygulanır; Firebase statik arşivleri default görünürlükle gelir.
- iOS full dylib 27,218, auth dylib 4,216 global tanımlı sembol taşır (`nm -gU`).
- Firebase C++ arşivlerinin `firebase_app`'ten çözdüğü benzersiz undefined sembol sayıları: auth 67,
  firestore 60, storage 59, database 70, functions 51. `firebase_app` 1,694 global sembol tanımlar.
  Split adaylarında Core bu sembolleri export etmek zorundadır (#83).

## Bakım bedeli ve öneri

| Platform | Ölçülen universal bedeli (auth kullanıcısı için) | Split bedeli |
| --- | --- | --- |
| Android | Native: +1.41 MB APK (+1.6%), +0.37 MB deflate. Maven seçimi zaten GDScript/export tarafında; asıl fark (+7.99 MB) native topolojiden bağımsız. | Core export listesi, çok DSO'lu `libc++_shared`, kayıt sırası ve godot-cpp izolasyonu; tasarruf en fazla 1.41 MB. |
| iOS | Native: +15.8 MB unpacked (+17.4%), +5.7 MB imzasız IPA (+22.3%). | Ortak ObjC/Swift framework sahipliği, `@rpath`/embedding/signing, dar `-force_load`; tasarruf ölçülür ölçüde büyük. |

Öneri (karar #90'da verilir): Android'de universal native güçlü aday; ancak a2'nin cihazda yüklenip
initialize ettiği kanıtlanmadan seçili Maven avantajı iddia edilmez. iOS'ta native fark büyük olduğu için split
adayları (#84) değerlendirmeye değer. Kullanıcının belirlediği bir MiB/yüzde eşiği yoktur; bu rapor eşik koymaz.

## Açık kalanlar

- a2 cihaz/emulator yükleme ve `App::Create` testi (disk ve cihaz eksikliği).
- İmzalı IPA ve App Store thinning boyutu.
- Moonlight `docs/app-size.md` takibi bu görevde yapılmadı; başka depo değiştirilmedi.

## Yeniden üretme

```sh
bash build/probes/package-size/build_native.sh          # auth/full native, link logları
bash build/probes/package-size/android_relink.sh        # link map ve --gc-sections denemesi
python3 build/probes/package-size/macho_map.py build/probes/package-size/full/ios/link.map
build/probes/fixture/make_fixture.sh <out> <auth|full> <modules>
godot --headless --editor --install-android-build-template --export-release Android export/android/FirebaseProbe.apk
godot --headless --export-release iOS export/ios/FirebaseProbe.xcodeproj
```

Probe betikleri `build/` altında kalır; komutlar bu rapordaki sonuçları üretmek için yeterlidir.
