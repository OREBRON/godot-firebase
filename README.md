# Godot Firebase

Godot 4.7.2 için Firebase eklentisi. Firebase C++ SDK 13.13.0
(iOS'ta Firebase iOS SDK 12.19.1) kullanır. GDScript API'leri modüllere
ayrılmıştır; mevcut native build seçilen modülleri tek kütüphaneye bağlar:

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
Birbirine eklenebilen ZIP düzeni geliştirme hedefidir; mevcut tek modül
ZIP'leri birlikte kurmak native dosyaların üzerine yazar. Geçişin durumu
[modüler release raporunda](docs/verification/modular-release.md) kayıtlıdır.

## Mevcut sürümü oyuna ekleme

1. `tools/bootstrap.sh`, ardından modül seçerek derle:
   ```bash
   # Gereken seçime ait satırı çalıştır; örneklerin her biri ayrı build'dir.
   tools/build.sh --modules auth
   tools/build.sh --modules auth,firestore
   tools/build.sh --modules auth,database
   tools/build.sh --modules auth,firestore,storage,database,functions
   tools/package.sh   # son build'i build/dist/ altında paketler
   ```
2. Paketi oyunun kök dizinine aç; yalnızca derlenen modüllerin klasörleri
   gelir. Elle API klasörü silmek native içeriği azaltmaz. Native build ve
   export bağımlılıklarının seçilen listesi `bin/modules.txt` içinde;
   platform çıktıları bu listeyle eşleşmeli. Varsayılan platformlar iOS ve macOS'tur;
   Android için aşağıdaki `--platforms` örneğini kullan. Modül seçimini
   değiştirirken eski `addons/firebase/bin/` çıktısını build öncesinde
   temizle ve dağıtılacak tüm platformları aynı modül listesiyle derle.
   Mevcut paketleyici eski platform çıktısını veya mixed build'i reddetmez.
3. Proje ayarlarında eklentiyi aç. `Firebase` autoload'u eklenir.
4. Firebase konsolundan `GoogleService-Info.plist` indir, `res://` köküne koy
   (dosya adı birebir aynı kalmalı). iOS export ayarlarında:
   - `firebase/sign_in_with_apple` açıksa `entitlements/additional` içine
     `<key>com.apple.developer.applesignin</key><array><string>Default</string></array>`
   - `firebase/sign_in_with_game_center` açıksa `entitlements/game_center`
   - Minimum iOS 15.
5. Firestore kullanıyorsan `templates/firestore.rules` kurallarını Firebase
   projesine ayrıca yükle; `templates/` mevcut eklenti ZIP'ine dahil değildir.
   Diğer ürünlerin erişim kurallarını oyununa göre yapılandır.
6. Functions varsayılan bölgesi `us-central1`. Başka bölge için proje ayarı
   `firebase/functions/region` ekle.

### Android

Android SDK (platform 35), NDK, JDK ve Godot Android Gradle build template'i
gerekir. `ANDROID_HOME` SDK dizinine işaret etmeli. Kurulu NDK varsayılan
28.1.13356709 değilse `NDK_VERSION` ortam değişkenini ayarla:

```bash
ANDROID_HOME="$HOME/Library/Android/sdk" NDK_VERSION=28.2.13676358 \
  tools/build.sh --platforms android,macos --modules auth,firestore
tools/package.sh
```

Android build'i oyun bilgisi almaz; aynı `.so` ve AAR her oyunda kullanılır.
Firebase konsolundan oyunun Android paket kimliğine ait `google-services.json`
dosyasını indirip projeye koy (varsayılan `res://google-services.json`; export
preset'indeki `firebase/google_services_json` seçeneğiyle değiştirilebilir).
Export eklentisi dosyayı pakete ekler. Uygulama açılırken çalışan paket
kimliğine ait client seçilir ve Firebase App bu değerlerle başlatılır.
Dosya yoksa veya paket kimliğine ait client, `mobilesdk_app_id` ya da API key
eksikse export penceresi uyarı gösterir. Godot 4.7 export eklentisi export'u
durduramaz; uygulama bu durumda Firebase'i başlatmaz ve hatayı loglar. AAR
yalnızca Java köprüsünü ve bütün modüllerin ProGuard kurallarını taşır;
Firebase kaynak XML'i üretilmez. Android export preset'inde **Use Gradle
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

## Birlikte kurulabilen paketler (hedef; henüz yayın kabulü yok)

Bu bölüm #90 platform kararı ve #67 paket/import kabulü sonrasında uygulanacak
kurulumu tarif eder. Bugün yukarıdaki kombinasyon build'ini kullan.

| Paket | Seçilen API |
| --- | --- |
| `godot-firebase.zip` | Beş modülün tümü |
| `godot-firebase-auth.zip` | Auth |
| `godot-firebase-firestore.zip` | Firestore |
| `godot-firebase-storage.zip` | Storage |
| `godot-firebase-database.zip` | Realtime Database |
| `godot-firebase-functions.zip` | Functions |

Her tek modül ZIP'i ortak Core, eklenti/export dosyaları ve ilgili platform
çıktılarını içerir; **ayrıca Core indirilmez**. Aynı `build_id` içindeki ortak
yollar aynı baytları taşır, modül yolları birbirinden ayrıdır. Full paket
bu beş paketin dosya birleşimidir. Bu eşitliklerin testleri henüz #67'de
bekliyor; mevcut ZIP'lerde bu sözleşme veya `build_id` kontrolü bulunmaz.

Hedef release'te aşağıdaki seçimin ZIP'lerini aynı oyun köküne aç:

| Oyun ihtiyacı | Açılacak paketler |
| --- | --- |
| Auth-only | `godot-firebase-auth.zip` |
| Auth + Firestore | `godot-firebase-auth.zip` + `godot-firebase-firestore.zip` |
| Auth + Database | `godot-firebase-auth.zip` + `godot-firebase-database.zip` |
| Full | `godot-firebase.zip` |

Örneğin Auth + Firestore için, paketler ve oyun kökü aynı dizindeyken:

```bash
unzip -o godot-firebase-auth.zip -d .
unzip -o godot-firebase-firestore.zip -d .
```

Ortak dosyalar aynı olduğu için aynı build'i tekrar açmak ve bu iki paketi
ters sırada açmak aynı sonucu vermelidir. Eklentiyi bir kez etkinleştir;
yalnız **tek `Firebase` autoload** olmalıdır. Modül başına autoload ekleme.
Oyun JSON/plist dosyalarını oyunda tut; eklenti release ZIP'leri bunları
taşımaz. Android/iOS oyun konfigürasyon adımları yukarıdakiyle aynıdır.

### Modül kaldırma ve sürüm yükseltme

Hedef paket düzeninde oyunu durdurup Godot editörünü kapat; örneğin Firestore'u
kaldırmak için `addons/firebase/firestore/` klasörünü kaldır. Ürüne ait native
descriptor, binary ve metadata bu klasörün sahipliğinde olmalıdır; ortak
Core/export dosyalarını kaldırma. Editörü yeniden açtığında
`Firebase.firestore == null` olur. API'nin silinmesi universal platformdaki
ortak native binary'yi küçültmez. Çalışırken native modül unload desteklenmez.

Full paketi tekrar açmak silinen modülü geri getirir. Azaltılmış seçimi
korumak için yalnız kalan modüllerin paketlerini kullan. Mevcut monolitik
sürümde klasör silmek API'yi kapatır; `bin/modules.txt` ve native/Maven ürün
seçimini değiştirmez. Native içeriği azaltmak için kalan seçimi yeniden derle
ve eski eklenti klasörünü temiz değiştir.

Yeni build'e yükseltirken bütün seçili modülleri birlikte değiştir:

1. Oyun projesini yedekle veya değişikliklerini commit et. Oyunu ve editörü kapat.
2. JSON/plist ve oyun betiklerinin `addons/firebase/` dışında olduğunu doğrula.
3. Eski `addons/firebase/` klasörünü bütünüyle kaldır.
4. İhtiyaç duyduğun ZIP'lerin **tamamını aynı `build_id`** içeren release'ten aç.
5. Editörü aç; eklenti ve tek autoload'u, seçili API'leri ve mobil export'u kontrol et.

ZIP açmak eski dosyaları silmez; tek bir modülü yeni build'den açarak upgrade
yapma. Hedef build kimliği kaynak commit'i, pinned SDK hash'leri ve build
girdilerinden üretilir; yalnız dosya adı veya release tag'i uyumluluk kanıtı
değildir. Mixed-build reddi #85/#86'da bekliyor.

Eski monolitten ilk geçişte de bu temiz kurulum adımlarını uygula. Oyununda
elle eklenmiş eski `.gdextension` tanımlarını, eklentiye ait Android AAR
kopyalarını ve export bağımlılıklarını yeni kurulumla birlikte bırakma.
`Firebase.auth` ve diğer modül API adları korunur; kaldırılan modülü kullanan
oyun kodunu da güncelle. `.godot/` içindeki elle üretilmiş extension kayıt
listesini taşımak yerine editörün yeni dosyaları taramasını sağla.

### Platform seçimi ve boyut bedeli

Platform kararı **henüz verilmedi**; kullanıcı cihaz kanıtını bekliyor (#90).
Android için universal native öneriliyor; iOS'ta ayrı modül extension'ları
değerlendiriliyor. İki platform aynı kullanıcı ZIP düzenini kullanabilir.
Universal seçilen platformda Auth-only paketi tüm ürünlerin ortak native
kodunu taşıyabilir; kullanılmayan native ürünlerin dışlandığı vaat edilmez.
Seçili Maven bağımlılıklarıyla full native'in açılması Android cihazında
henüz doğrulanmadı.

Mevcut monolitik Auth/full fixture karşılaştırması (hedef ZIP boyutları değil):

| Ölçüm | Full − Auth farkı |
| --- | ---: |
| Android native `.so` / APK, Maven sabit | 1,405,384 B / APK +%1.63 |
| Android Maven farkı, full native sabit | 7,989,069 B / APK +%9.10 |
| iOS native `.dylib` | 15,800,592 B |
| iOS unpacked `.app` | 15,840,069 B / +%17.4 |
| iOS imzasız IPA (`zip -9`) | 5,708,044 B / +%22.3 |

iOS split prototipinde Core + Auth, universal full native'den 14,798,240 B
küçüktür; bu bir native prototip ölçümüdür, imzalı IPA veya App Store indirme
boyutu değildir. Ayrıntılar: [boyut raporu](docs/verification/modular-size.md),
[native prototip raporu](docs/verification/modular-native.md).

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

Depo kökündeki Makefile mevcut `tools/` betiklerini çağırır. `make` kullanılabilir
hedefleri gösterir:

```bash
make bootstrap
make build MODULES=auth,firestore PLATFORMS=ios,macos
make test GODOT=/Applications/Godot.app/Contents/MacOS/Godot
make package

# Android SDK platform 35 ve JDK gerektirir.
make android-aar ANDROID_HOME="$HOME/Library/Android/sdk"
make test-android-aar ANDROID_HOME="$HOME/Library/Android/sdk"
```

`MODULES` ve `PLATFORMS` verilmezse `tools/build.sh` varsayılanları kullanılır.
`GODOT`, `SCONS`, `ANDROID_HOME` ve `NDK_VERSION` ortam değişkeni veya `make`
argümanı olarak verilebilir. `make package`, mevcut build'i `bin/modules.txt`
listesine göre paketler.

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
eklenir; branch ve PR çalışmaları paket yüklemez. Bu mevcut varyantlar
birbirine eklenebilen paketler değildir; #68'de tek release build'inden
bileşenleri paketleyen CI düzenine geçiş planlıdır. Android CI build/test
akışı henüz eklenmedi. Elle
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
- Auth-only/full boyut ölçümü yapıldı; yukarıdaki tablo fixture sonuçlarıdır.
  İmzalı IPA/App Store thinning ve hedef altı ZIP'in boyutları doğrulanmadı.
- Android: JNI, AAR, bağımlılıklar ve arm64-v8a build'i eklendi; Android
  cihazda export, Firebase başlatma ve modül istekleri henüz doğrulanmadı.
- Birleşebilir paketlerin path/hash, import sırası, tekrar import, Core-only,
  kaldırma ve mixed-build testleri #67'de; nihai platform kararı #90'da bekliyor.
  Cihaz ve release/minification kabulü #55/#59'da açık. Güncel kanıt ayrımı
  [modüler release raporunda](docs/verification/modular-release.md) bulunur.
