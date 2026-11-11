# Godot Firebase

Godot 4.7.2 için Firebase eklentisi. Firebase C++ SDK 14.1.0
(iOS'ta Firebase iOS SDK 13.1.1) kullanır. GDScript API'leri modüllere
ayrılmıştır; mevcut native build seçilen modülleri tek kütüphaneye bağlar:

| Modül | Klasör | Native sınıf | İçerik |
|---|---|---|---|
| core (zorunlu) | `core/` | `FirebaseAppNative` | App başlatma, görev ve sonuç tipleri |
| auth | `auth/` | `FirebaseAuthNative` | Anonim, Google, Play Games, Game Center, Apple, hesap bağlama, silme |
| firestore | `firestore/` | `FirebaseFirestoreNative` | Doküman, sorgu, batch, dinleyici, cache/pending-write gözlemi |
| storage | `storage/` | `FirebaseStorageNative` | Dosya yükleme/indirme (bayt), indirme URL'si, metadata, silme |
| database | `database/` | `FirebaseDatabaseNative` | Realtime Database, başlangıç persistence seçimi, bağlantı/presence |
| functions | `functions/` | `FirebaseFunctionsNative` | Callable HTTPS fonksiyon çağrısı |
| analytics | `analytics/` | `FirebaseAnalyticsNative` | Event, kullanıcı özelliği, collection ve consent |
| remote_config | `remote_config/` | `FirebaseRemoteConfigNative` | Defaults/fetch/activate, tipli değer, realtime güncelleme |
| crashlytics | `crashlytics/` | `FirebaseCrashlyticsNative` | Açık nonfatal rapor, platform native crash, collection ve rapor kontrolü |

Sekiz ürünün API/mock katmanı mevcuttur. Analytics ve Remote Config pinned
C++ SDK'yı; Crashlytics Android Java/NDK ve iOS Objective-C++ köprülerini kullanır.
Native derleme ile cihaz/console kabulü ayrı izlenir; güncel kapsam ve testler
[SDK yetenekleri raporundadır](docs/verification/sdk-capabilities.md).
Cihazlarda henüz doğrulanmadı (bkz. [Doğrulanmamış noktalar](#doğrulanmamış-noktalar)).
Birbirine eklenebilen ZIP düzeni geliştirme hedefidir; mevcut tek modül
ZIP'leri birlikte kurmak native dosyaların üzerine yazar. Geçişin durumu
[modüler release raporunda](docs/verification/modular-release.md) kayıtlıdır.

## Sürümleme

Eklentinin kendi [SemVer](https://semver.org/lang/tr/) sürümü vardır
(`addons/firebase/plugin.cfg`, tag `v<sürüm>`). Godot ve Firebase sürümleri
`tools/versions.env` içinde sabitlenir ve release başlığında yazılır:

- **MAJOR:** oyunu bozabilecek değişiklik: GDScript API silme/yeniden adlandırma,
  asgari Godot sürümünün yükselmesi veya platform şartını değiştiren Firebase
  ana sürümü (ör. Android minSdk).
- **MINOR:** geriye uyumlu özellik veya Firebase ara sürümü.
- **PATCH:** hata düzeltmesi veya Firebase yama sürümü.

Yayımlanmış bir release'in dosyaları değiştirilmez; her yeni build yeni sürüm
alır, böylece ZIP ve Crashlytics sembolleri tek build'e bağlı kalır.

| Eklenti | Godot | Firebase C++ | Firebase iOS |
|---|---|---|---|
| 1.0.0 | 4.7.2 | 14.1.0 | 13.1.1 |
| `v4.7.2` (eski adlandırma) | 4.7.2 | 13.13.0 | 12.19.1 |

## Mevcut sürümü oyuna ekleme

### Desktop editöründe geliştirme

Linux x86_64, Windows x86_64 ve macOS arm64/x86_64 editörleri için hazır
boş GDExtension kütüphaneleri depoda **Git LFS** ile tutulur. Projeyi açmak
için C/C++ derleyicisi veya Firebase SDK kurulumu gerekmez:

```bash
git lfs install
git lfs pull
```

Godot 4.7.2 ile projeyi aç. `.gdextension` dosyası `windows.x86_64`,
`linux.x86_64`, `macos.arm64`, `macos.x86_64` etiketleriyle uygun kütüphaneyi
seçer; debug/release aynı boş uzantıyı kullanır. Bu seçim Godot'un
[resmi feature-tag sözleşmesini](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html#libraries-section)
izler. Uzantı native Firebase sınıfı kaydetmez; kurulu ürün API'leri mevcut
GDScript mock backend'leriyle çalışır. Desktop istekleri yerel mock verisi
kullanır; gerçek Firebase bağlantısı iOS/Android native build'ine aittir.

Kaynak `src/desktop/godot_firebase_stub.c`, derleme aracı
`tools/build_desktop_stub.py` içindedir. Yalnız kütüphaneleri değiştiren
geliştiricinin Python 3 ve C derleyicisine ihtiyacı vardır: macOS'ta Xcode
Command Line Tools, Linux'ta GCC/Clang, Windows'ta LLVM Clang + lld-link.
Firebase SDK veya godot-cpp indirmek gerekmez:

```bash
# Her komut ilgili işletim sisteminde çalışır; macOS iki mimariyi de üretir.
python3 tools/build_desktop_stub.py --platform macos --arch arm64
python3 tools/build_desktop_stub.py --platform macos --arch x86_64
python3 tools/build_desktop_stub.py --platform linux --arch x86_64
# Windows / PowerShell:
python tools/build_desktop_stub.py --platform windows --arch x86_64

# Windows/Linux için macOS'tan cross-build alternatifi (Zig 0.15.2):
python3 tools/build_desktop_stub.py --platform windows --arch x86_64 --cc "/path/to/zig cc"
python3 tools/build_desktop_stub.py --platform linux --arch x86_64 --cc "/path/to/zig cc"
```

Çıktılar doğrudan `addons/firebase/bin/<platform>/` altındaki dört LFS
dosyasına yazılır. `make desktop-stub` mevcut host için yeniden derler;
`PLATFORM` ve `ARCH` ile hedef seçilebilir. `tools/build.sh --platforms macos`
iki Mac stub'ını aynı kaynakla üretir; `linux` ve `windows` da `--platforms`
listesinde seçilebilir (`CC` ile cross compiler verilebilir).

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/run_tests.sh
# Windows'ta GODOT ortam değişkenini Godot konsol EXE yoluna ayarla:
python tools/run_tests.py
```

Testler editör importunu, uzantının gerçekten yüklenmesini, dört kütüphanenin
varlığını, otomatik mock başlangıcını ve stok GDScript testlerini doğrular.
Eksik LFS binary, import/script hatası ve timeout başarısız sayılır.
[Kabul koşulları ve doğrulama kanıtı](docs/verification/desktop-libraries.md).

### Mobil native paketi

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
   değiştirirken eski mobil `addons/firebase/bin/android/` ve `bin/ios/`
   çıktısını build öncesinde temizle; LFS desktop stub'larını koru ve
   dağıtılacak tüm mobil platformları aynı modül listesiyle derle.
   Mevcut paketleyici eski platform çıktısını veya mixed build'i reddetmez.
3. Proje ayarlarında eklentiyi aç. `Firebase` autoload'u eklenir.
4. Firebase konsolundan `GoogleService-Info.plist` indir, `res://` köküne koy
   (dosya adı birebir aynı kalmalı; `BUNDLE_ID` export preset'inin
   `application/bundle_identifier` değeriyle eşleşmeli, aksi halde export Xcode
   build'ini durdurur). iOS export ayarlarında:
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

Android SDK (platform 35), NDK, JDK 17 ve Godot Android Gradle build template'i
gerekir. `ANDROID_HOME` SDK dizinine işaret etmeli. Kurulu NDK varsayılan
28.1.13356709 değilse `NDK_VERSION` ortam değişkenini ayarla:

```bash
ANDROID_HOME="$HOME/Library/Android/sdk" NDK_VERSION=28.2.13676358 \
  tools/build.sh --platforms android,macos --modules auth,firestore
tools/package.sh
```

Depodaki `.sdkmanrc` Temurin JDK 17'yi sabitler. SDKMAN kurulu bir kabukta
`sdk env install` komutu sürümü kurup seçer; `JAVA_HOME` ve `PATH` buna göre
ayarlanır. CI da aynı sürümü SDKMAN üzerinden seçer.
Reusable AAR derlemesi depodaki SHA-256 doğrulamalı Gradle 9.3.1 wrapper'ını
kullanır. Oyun export'u Godot 4.7.2'nin kurulu Android Gradle template'ini kullanır.
En az bir Firebase modülü seçiliyken export helper'ı standart `config.gradle`
içindeki eski Kotlin sürümünü yönetilen bir blokla 2.4.0'a yükseltir ve
`settings.gradle` içine R8 9.1.29 override'ı ekler; AGP sürümünü değiştirmez.
Firebase modüllerinin tamamı seçimden çıkarıldığında kendi bloklarını kaldırır.
Değiştirilmiş yönetilen bloklar veya desteklenmeyen özel template biçimleri hata
üretir; bu dosyaları elle aynı ayarlarla yamamak gerekmez. Kotlin 2.4.x zaten
seçiliyse korunur; daha yeni Kotlin hattı ayrıca uyumluluk doğrulaması gerektirir.
Bu eşleşme [Android Kotlin/R8 tablosuna](https://developer.android.com/build/kotlin-support)
ve [R8'in resmi Gradle override yöntemine](https://r8.googlesource.com/r8/+/refs/heads/main/README.md#replacing-r8-in-android-gradle-plugin)
dayanır. Yerel sentetik uygulama fixture'ı AGP 8.6.1, Gradle 8.11.1, Kotlin 2.4.0
ve gerçekten kullanılan R8 9.1.29 ile geçti; gerçek Godot export/cihaz kabulü
ayrı kalır. Crashlytics entegrasyonu Google Services 4.5.0 / Crashlytics Gradle
3.0.8 ve Crashlytics/NDK 21.0.1 sürümlerini seçer.

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
Analytics/Crashlytics seçildiğinde export, oyunun JSON'undan gereken Firebase
kaynaklarını üretir; Crashlytics ayrıca oyun Gradle projesine sabit sürümlü
plugin yapılandırmasını ekler. Analytics'in uygulama başlangıcındaki erken
event'leri doğru App ID ile ilişkilendirmesi için Firebase'in
[önerdiği kaynak tabanlı yapılandırma](https://firebase.google.com/docs/projects/multiprojects#ensure_reliable_reporting_for_analytics)
kullanılır. Bu config reusable AAR'a girmez. Android export preset'inde **Use Gradle
Build** açılmalı, yalnızca **arm64-v8a** etkin olmalı; Gradle export eklentisi
AAR'ı ve Firebase Maven bağımlılıklarını ekler. Android'da anonim giriş ve
diğer çekirdek modüller derlenir; Apple / Game Center girişleri Android'da
desteklenmez. `sign_in_with_google()` / `link_with_google()` platform credential
arayüzünü kullanır. Proje ayarı `firebase/auth/google_web_client_id`, iOS için
ayrıca `firebase/auth/google_ios_client_id` oyunun OAuth kayıtlarıyla eşleşmelidir.
Play Games helper için `firebase/auth/play_games_enabled=true` ve
`firebase/auth/play_games_app_id` ayarlanır; `sign_in_with_play_games_platform()` /
`link_with_play_games_platform()` taze server auth code edinir. Oyunun kendisinin
edindiği code için mevcut `sign_in_with_play_games(code)` / `link_with_play_games(code)`
API'leri korunur. İkinci eşzamanlı credential UI isteği `ERR_BUSY`, iptal
`ERR_CANCELLED` döner. Hesaplar veya oyun verisi otomatik birleştirilmez.

## Yeni ürünlerin geliştirme paketleri

```bash
tools/build.sh --modules analytics,remote_config,crashlytics --platforms ios,android,macos
tools/package.sh
```

Gereken ürün birleşimini tek build'de seç; mevcut ZIP'leri üst üste kurma.
Tekil yeni ürün adları `godot-firebase-analytics.zip`,
`godot-firebase-remote-config.zip` ve `godot-firebase-crashlytics.zip` olur.
Sekiz ürün birlikte seçilirse çıktı `godot-firebase.zip` olur; diğer her
birleşim seçilen ürünlerin adını alır (örneğin `godot-firebase-auth-firestore.zip`). Paketleyici
geçersiz/tekrarlı modül adlarını reddeder, seçilmeyen API/mock klasörlerini ve
oyun JSON/plist dosyalarını dışlar. Native platform çıktılarının aynı seçimden
geldiğini build sahibi sağlamalıdır; stale/mixed build doğrulaması halen yoktur.

Release workflow'u (`build.yml`) sekiz ürünün tümünü tek monolit olarak iOS,
Android ve macOS için derler. Windows ve Linux editör kütüphaneleri LFS'den
gelir. Release'in `godot-firebase.zip` dosyası her zaman bütün modülleri
içerir. `v4.7.2` release'indeki `godot-firebase.zip` bu kuraldan önce
yayımlandı ve altı ürün içerir; Storage ve Database o pakette yoktur. ZIP'leri
üst üste kurma; seçilen ürünleri birlikte kullanmak için tek ZIP'i aç. Bu,
dokuz adet birleşebilir paket hedefinin kabulü değildir.

#224 takip release hedefi sekiz tekil ürün + full, toplam dokuz ZIP'tir.
Birleşebilir native topoloji, ortak path/hash, full=union ve build-ID kabulü
#90/#85/#86/#67/#68 sonuçlarını bekler. Aşağıdaki bölüm bu hedefi tarif eder;
yeni geliştirme ZIP'leri bu kabulü tamamlamaz.

## Birlikte kurulabilen paketler (hedef; henüz yayın kabulü yok)

Bu bölüm #90 platform kararı ve #67 paket/import kabulü sonrasında uygulanacak
kurulumu tarif eder. Bugün yukarıdaki kombinasyon build'ini kullan.

| Paket | Seçilen API |
| --- | --- |
| `godot-firebase.zip` | Bütün modüller |
| `godot-firebase-auth.zip` | Auth |
| `godot-firebase-firestore.zip` | Firestore |
| `godot-firebase-storage.zip` | Storage |
| `godot-firebase-database.zip` | Realtime Database |
| `godot-firebase-functions.zip` | Functions |
| `godot-firebase-analytics.zip` | Analytics |
| `godot-firebase-remote-config.zip` | Remote Config |
| `godot-firebase-crashlytics.zip` | Crashlytics |

Her tek modül ZIP'i ortak Core, eklenti/export dosyaları ve ilgili platform
çıktılarını içerir; **ayrıca Core indirilmez**. Aynı `build_id` içindeki ortak
yollar aynı baytları taşır, modül yolları birbirinden ayrıdır. Full paket
bütün tek modül paketlerinin dosya birleşimidir. Bu eşitliklerin testleri henüz #67'de
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
var id: int = Firebase.firestore.listen_doc(path, func(r: FirebaseResult): print(r.value.data if r.ok else r.error_message))
Firebase.firestore.remove_listener(id)

var file := "users/%s/avatar.png" % uid
await Firebase.storage.upload_bytes(file, png_bytes, "image/png").wait()
var bytes: PackedByteArray = (await Firebase.storage.download_bytes(file).wait()).value

await Firebase.database.set_value("rooms/r1/players/%s" % uid, {"ready": true, "joined": FirebaseDatabase.SERVER_TIMESTAMP}).wait()
var key: String = (await Firebase.database.push_value("rooms/r1/chat", {"text": "selam"}).wait()).value
var room: int = Firebase.database.listen_value("rooms/r1", func(r: FirebaseResult): print(r.value.value if r.ok else r.error_message))
Firebase.database.remove_listener(room)

var reward: FirebaseResult = await Firebase.functions.call_function("claimDailyReward", {"day": 3}).wait()
```

- Her istek `FirebaseTask` döner; `await task.wait()` bir `FirebaseResult`
  verir: `ok`, `value`, `error_code`, `error_message`. Negatif kodlar
  eklentiden gelir (`FirebaseResult.ERR_*`), pozitifler Firebase'den.
- Dinleyici callback'i de `FirebaseResult` alır. Kural reddi veya oturum kapanması
  gibi bir hatada `ok == false`, `value == null` olan tek sonuç gelir ve dinleyici
  durur; `value` okumadan önce `ok`'u kontrol et.
- Firestore özel değerleri: `FirebaseValue.timestamp()`, `server_timestamp()`,
  `increment()`, `delete_field()`. Zaman damgaları okunurken
  `{__firebase__ = "timestamp", seconds, nanos}` sözlüğü olarak gelir.
  Zaman damgası 0001-01-01 ile 9999-12-31 arasında olmalı. `server_timestamp()`,
  `increment()` ve `delete_field()` dizi içinde ve sorgu değerinde kullanılamaz.
  `__firebase__` anahtarlı her sözlük özel değer sayılır: Database, Functions
  veya oyuncudan gelen bir sözlüğü kontrol etmeden `set_doc()`/`update_doc()`'a
  verirsen `{__firebase__ = "delete"}` alanı siler, `"increment"` sayıyı artırır.
  Böyle veriyi yazmadan önce beklediğin alanlara ayıkla.
- Firestore sorgu alanları ve `update_doc()` anahtarları noktalı alan yoludur
  (`"profile.level"`): boş parça ve `~ * / [ ]` içeremez. Yazılan alan adları
  (ve `update_doc()` yol parçaları) `__` ile hem başlayıp hem bitemez (`__x__`). `limit` en fazla
  2147483647; `limit <= 0` limitsiz demek.
- Firestore tipleri: null, bool, int, float, String, PackedByteArray, Array
  (iç içe dizi yok), Dictionary (String anahtarlı).
- Database ve Functions tipleri: null, bool, int, sonlu float (NaN/Inf yok), String, Array
  (packed diziler dahil), Dictionary (String anahtarlı). Database anahtarları
  `. # $ [ ] /` içeremez; `FirebaseDatabase.SERVER_TIMESTAMP` sunucu zamanını
  Unix milisaniye olarak yazar.
- Storage metadata sonucu `{path, name, size, content_type, updated}`;
  `updated` Unix milisaniye. `download_bytes` varsayılan olarak en fazla 10 MB okur;
  `max_size` tamponu baştan ayrıldığı için en fazla 100 MB (`FirebaseStorage.MAX_DOWNLOAD`) olabilir.
- Geçersiz veri native katmana ulaşmadan `ERR_INVALID_ARGUMENT` ile döner.
- Silinen modülün özelliği `null` olur (`Firebase.firestore == null`). Bu yüzden
  modül özellikleri (`Firebase.auth`, `Firebase.storage`, ...) tipsizdir;
  sonuçları tipli değişkene ata (`var r: FirebaseResult = await ...`) ya da
  `var auth: FirebaseAuth = Firebase.auth`.
- Editörde ve masaüstünde bellek içi mock çalışır (`Firebase.is_mock("auth")`);
  Windows/Linux/macOS kütüphaneleri Firebase içermeyen boş uzantılardır. Dışa aktarılmış
  oyunda mock kullanan her modül açılışta `push_warning` verir: veri Firebase'e
  gitmez ve kapanınca kaybolur. Mobilde native
  başlatılamazsa mock'a düşülmez; istekler `ERR_UNAVAILABLE` döner.
- Mock'lar cihazdaki SDK davranışını izler, sunucuyu taklit etmez:
  - Güvenlik kuralları ve Firestore bileşik indeksleri uygulanmaz; editörde her
    okuma/yazma izinlidir. Kuralları Firebase Emulator Suite ile ayrıca test et.
    Reddi `fail_next()` ile taklit et (`Firebase.backends.firestore.fail_next(7, "denied")`):
    sonraki istek ya da sonra başlatılan Firestore/Database dinleyicisi bu hatayı alır.
  - Veri bellek içidir; her çalıştırma temiz kurulumdur (oturum, Firestore,
    Database, Storage ve Remote Config değerleri saklanmaz). Test verisini koddan
    `Firebase.backends.firestore.documents`, `database.root` veya `storage.files`
    üzerinden doldur.
  - Functions yalnızca `Firebase.backends.functions.handlers` içine kaydedilen
    yerel fonksiyonları çağırır. Veri ve sonuç JSON'dan geçer: handler sayıları
    float görür; tam sayı sonuçlar int, packed diziler Array döner, anahtarlar sıralanır.
  - Storage indirme URL'leri (`https://storage.mock/...`) indirilemez; içerik tipi
    verilmeyen yükleme `application/octet-stream` olur.
- Auth açılışta `state_changed` sinyalini bir kez verir (oturum yoksa `{}`).
  Anonim kullanıcı tekrar anonim giriş yaparsa aynı uid döner ve sinyal gelmez.
  `firebase/auth/mock_platform` proje ayarı (`""` varsayılan, `"android"`, `"ios"`)
  editörde o platformda olmayan sağlayıcıları native gibi `ERR_UNSUPPORTED` ile reddeder;
  değişiklik yeniden başlatmada geçerli olur.
- Firestore sorgusu `order_by` yoksa eşitsizlik alanına, sonra doküman ID'sine göre
  sıralanır; `limit` buna göre keser. Aralık filtreleri farklı tipleri eşleştirmez,
  `!=` null ve eksik alanı dışlar, `1 == 1.0` doğrudur.
- Realtime Database değerleri cihazdaki gibi gelir: sözlük anahtarları bayt
  sırasındadır (`"10"`, `"9"`'dan önce); `0..n` anahtarlı map'ler boşlukları `null`
  olan Array, seyrek diziler sözlük olarak döner. `.info/connected` önce `false`,
  bağlantı kurulunca `true` olur; `set_network_enabled(true)` görevi bağlantıdan önce
  biter. Değer dinleyicisi yalnızca değer değişince çağrılır; bağlantı koparken
  onDisconnect işlemleri yerelde hemen görünür.
- Hesap açtıran oyunlar App Store kuralı gereği hesap silme sunmalıdır:
  `Firebase.auth.delete_account()`. Apple ile bağlı hesapta önce
  `Firebase.auth.revoke_apple_token()` çağrılır: Apple sayfası bir kez açılır ve
  Apple belirteçleri iptal edilir (değer `true`); Apple bağlı olmayan hesapta arayüz
  açılmaz, değer `false` olur. Mock'ta `fail_next()` iptal/başarısızlığı taklit eder.

## Geliştirme

Firestore `get_doc`/`query` için `source="default"|"cache"|"server"` seçilebilir.
`query_snapshot()` sonuç metadata'sını boş sorguda da taşır; dinleyicilerde
`include_metadata_changes=true` cache ve pending-write değişimini gözler.
Yazma task'ı sunucu ACK'ini bekler; offline durumda pending kalabilir.
`wait_pending_writes()` çağrı anındaki yazmaları kapsar, sonraki yazmaları kapsamaz.
Yerel snapshot disk fsync veya sunucu ACK'i değildir.

Realtime Database persistence başlangıç proje ayarı
`firebase/database/persistence_enabled=false` ile belirlenir; ilk referanstan
önce uygulanır, runtime setter yoktur. `set_network_enabled()` komut başarısı
internet bağlantısı değildir. Yalnız `.info/connected` ve `.info/serverTimeOffset`
özel read/listen yollarıdır. `on_disconnect_set_value`, `on_disconnect_update_children`,
`on_disconnect_remove_value` ve `on_disconnect_cancel` task'ları kayıt/cancel ACK'i
döndürür. Oyun her bağlantıda yeniden kayıt yapar; ACK'ten sonra online yazan
[presence örneğine](examples/database_presence.gd) bak. Kayıt yürütülmüş sayılmaz.

```gdscript
# Yerel Analytics çağrısıdır; upload onayı değildir. Auth UID otomatik atanmaz.
await Firebase.analytics.log_event("level_end", {"level": 7}).wait()
await Firebase.analytics.set_consent({"analytics_storage": FirebaseAnalytics.GRANTED}).wait()

# Fetch aktif değerleri değiştirmez. Uygulama anını oyun seçer.
await Firebase.remote_config.set_defaults({"welcome": "Merhaba"}).wait()
await Firebase.remote_config.fetch().wait()
await Firebase.remote_config.activate().wait()
var welcome: FirebaseResult = await Firebase.remote_config.get_value("welcome").wait()
print(welcome.value.value, welcome.value.source)

# Explicit GDScript nonfatal; bütün Godot hataları otomatik raporlanmaz.
await Firebase.crashlytics.record_error("SaveError", "Save file unavailable").wait()
```

Analytics/Crashlytics export seçenekleri `firebase/analytics_collection` ve
`firebase/crashlytics_collection` SDK default / enabled / disabled seçer. Seçim
startup öncesi Android Manifest/iOS plist'e yazılır; verilmezse SDK varsayılanı
korunur. Runtime SDK override'ları uygulama çalışmaları arasında kalabilir;
özellikle Crashlytics disable çağrısı restart gerektirebilir. Taze kurulumda
başlangıçtan kapalı olma kabulünü runtime setter ile değiştirme.
Crashlytics log/nonfatal/send/delete başarıları yerel çağrıdır; rapor upload ACK'i
değildir. `check_unsent_reports()` collection açıkken false; kapalıyken SDK'nın
çalışma başına tek kontrolünü kullanır. Analytics breadcrumbs opsiyoneldir,
Auth veya Analytics API modülleri Crashlytics için zorunlu değildir. Android'de
pinned C++ App'in başlangıcı Analytics Java sınıflarını kullandığı için taban
Maven bağımlılığı korunur; API klasörünü kaldırmak collection'ı kapatmaz.

Crashlytics seçili build `debug_symbols=yes` kullanır, Android unstripped ELF ve
iOS dSYM dosyalarını `build/symbols/<selection>/` altında kimlikleriyle saklar
(`identity.json` yolları depo köküne görelidir). Semboller addon ZIP'ine katılmaz;
release'te yalnız o release'in seçim klasörü ayrı `godot-firebase-symbols.zip`
asset'i olarak yayımlanır ve oyun gerektiğinde dSYM'i `upload-symbols` ile
Crashlytics'e kendisi yükler. Oyun export'u kendi R8 mapping'ini saklar;
Godot engine frame'leri yalnız aynı export template'in sembolleriyle çözülebilir.
[Debug smoke ve açık symbol upload adımları](examples/crashlytics_smoke/README.md)
SDK build'inden ayrıdır; otomatik upload yapılmaz.

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
python3 tests/test_sdk_capability_packages.py
```

`MODULES` ve `PLATFORMS` verilmezse `tools/build.sh` varsayılanları kullanılır.
`GODOT`, `SCONS`, `ANDROID_HOME` ve `NDK_VERSION` ortam değişkeni veya `make`
argümanı olarak verilebilir. `make package`, mevcut build'i `bin/modules.txt`
listesine göre paketler.

iOS dağıtım paketi için `tools/package.sh --sign-ios` kullanılır. Bu seçenek
son paket içeriğindeki device/simulator framework'lerini ve debug/release
XCFramework'lerini Apple sertifikasıyla imzalar; ZIP'i tekrar açıp imzaları
doğrulamadan çıktıyı yayımlamaz. Bayraksız komut yerel geliştirme içindir ve
imzalı dağıtım garantisi vermez. Sertifika/Keychain kurulumu, Godot Xcode export'u
ve son IPA kontrolü: [iOS imzalama kabulü](docs/verification/ios-signing.md).
App Store'a yüklenecek son IPA, `tools/ios_signing.py verify-ipa ...
--team-id <oyun-ekibi> --distribution` ile ayrıca kontrol edilir; SDK için
kabul edilen Apple Development sertifikası uygulamanın dağıtım imzası yerine geçmez.

Auth içeren iOS build, `tools/build_google_signin_ios.sh` ile pinned kaynaklardan
GoogleSignIn bağımlılıklarını hazırlar; kurulu CocoaPods/Xcode gerekir, global araç
kurulmaz. Testler mock'larla çalışır. Native ClassDB signature gate'i editor
stub'da açıkça skipped raporlar; native parity sonucu sayılmaz.

### CI

`.github/workflows/desktop.yml`, GitHub-hosted Linux x86_64, Windows x86_64,
macOS arm64 ve Intel macOS runner'larında çalışır. Her job `tools/versions.env`
içindeki aynı Godot 4.7.2 editörünü resmi release'den indirir ve yayımlanan
SHA-512 ile doğrular. İlk kontroller doğrudan checkout'ta LFS ile gelen
kütüphanelere uygulanır: editör importu, Firebase mock başlangıcı ve stok
testleri. Sonra kaynak yeniden derlenir ve aynı kontroller yeni kütüphaneyle
tekrarlanır. Build öncesi test, bozuk hazır binary'nin CI'da gizlenmesini
önler. Push/main, PR ve manual tetiklenir; mobil SDK indirmez.

#### Mobil build (self-hosted runner)

`.github/workflows/build.yml` `[self-hosted, macOS, ARM64]` runner'da çalışır
(Xcode, `godot` 4.7.2, `uv`, Android SDK/NDK ve JDK 17 gerekir). SDK indirmeleri runner'da
`../godot-firebase-third-party` altında kalıcı tutulur; ilk çalışma ~2.2 GB
indirir. Her çalışma sekiz ürünün tümünü tek seçimle iOS, Android ve macOS
için derler, mock testlerini ve paket smoke testini koşar. CI iOS paketini
imzalamaz ve release yayımlamaz; runner'da imza sertifikası gerekmez. Paket oyunun
kök dizinine açılır. Cihazda Firebase runtime ve Crashlytics symbolication
kanıtı ayrı kabul işlerinde bekliyor.

#### Release (yerel Mac)

Release, imza anahtarı Keychain'inde olan Mac'te `tools/release.sh` ile yayımlanır:
tag'i oluşturup push et, tag'e checkout yap ve `tools/release.sh v4.7.2` çalıştır.
Betik temiz çalışma kopyasını ve tag eşleşmesini kontrol eder, iOS/Android/macOS'u
derler, testleri ve paket smoke testini koşar, iOS'u `--sign-ios` ile imzalar,
origin'deki tag'in HEAD'i gösterdiğini doğrular ve `godot-firebase.zip`,
`godot-firebase-symbols.zip`, `SHA256SUMS.txt` dosyalarıyla yeni release'i oluşturur.
Var olan release'in üzerine yazılmaz; betik reddeder, `plugin.cfg` sürümünü artır.
`IOS_SIGNING_IDENTITY` (tam Apple Distribution/Development sertifika adı veya SHA-1)
ve `IOS_SIGNING_TEAM_ID` ortam değişkenleri gerekir; `IOS_SIGNING_KEYCHAIN` isteğe bağlı Keychain yoludur.
`ANDROID_HOME` (platform 35, NDK 28.1.13356709), JDK 17 ve oturum açmış `gh` gerekir.
Eksik kimlik/anahtar, yanlış ekip, imzasız/ad-hoc, zaman damgasız veya bozuk paket
betiği durdurur. Yeni `.p8` gerekmez.

`.github/workflows/sdk-capabilities.yml` yalnız PR/manual geliştirme doğrulamasıdır.
Analytics, Remote Config ve Crashlytics tekil seçimlerini, telemetry
birleşimini, sekiz ürünün full seçimini (`full-eight`), Auth+Firestore ve Auth+Database
seçimlerini iOS/Android/macOS için derler; mock/paket testleri ve sembol doğrulaması
koşar. Kurulu platform 35, NDK 28.1.13356709, JDK, CocoaPods, Xcode ve Godot gerekir.
ZIP/semboller kısa ömürlü, imzasız workflow artifact'larıdır; dokuz-paket release yayımlamaz.
Bu workflow yerelde çalıştırılmış GitHub CI sonucu veya cihaz kabulü değildir.
Manual çalışmada `android_export_fixture=true`, yalnız full-eight job'ında
beş sentetik uygulama seçiminin debug/R8 APK fixture'ını çalıştırır: telemetry,
Auth+telemetry+Play Games, Auth-only, Remote Config-only ve Analytics-only.
Fixture aynı generic AAR ile toplam 10 APK üretir; Godot engine/native `.so`
içermez ve cihazda çalıştırmaz. Kurulu Android platform 36
ve build-tools 36.1.0 ister; Gradle 8.11.1 SHA-256 kontrolüyle çalışma dizinine
indirilir. Global SDK/JDK kurulmaz, Firebase'e rapor/sembol yüklenmez.

#### Modül paketleri (Linux + macOS self-hosted)

`.github/workflows/packages.yml` push/main, PR ve manual tetiklenir; yalnız
workflow artifact'ı üretir, release yayımlamaz. Dokuz seçim derlenir:
sekiz ürünün tümünü içeren `godot-firebase.zip` ve her ürün için tek
`godot-firebase-<ürün>.zip` (`auth`, `firestore`, `storage`, `database`,
`functions`, `analytics`, `remote-config`, `crashlytics`). Artifact
doğrudan paket ZIP'idir; oyunda **ya tek ürün ZIP'ini ya full ZIP'i** oyun
köküne aç. Her ZIP ayrı bir native seçimdir; iki ZIP'i üst üste açma.

| Job | Runner | Yaptığı iş |
| --- | --- | --- |
| `editor` | `[self-hosted, Linux, X64]` | Linux ve Windows editör kütüphanelerini bir kez derler; mock, Auth lifecycle ve paketleyici testleri |
| `package` | `[self-hosted, macOS, ARM64]` | Her seçim için iOS, Android ve macOS editör kütüphanelerini tek build'de derler; `tools/package.sh`, paket smoke testi ve yükleme |

Bir paketin iOS ve Android çıktıları aynı runner'da aynı build'den gelir;
paket farklı build'lerin mobil kütüphanelerini karıştırmaz. Linux ve Windows
editör kütüphaneleri Firebase içermez, bütün seçimlerde aynıdır. Workflow LFS
indirmez, paketteki her native dosya aynı çalışmada derlenir; commit'li LFS
kütüphanelerini `desktop.yml` test eder. Herhangi bir test, build veya smoke
adımı başarısız olursa workflow başarısız olur ve paket yüklenmez. Editör
kütüphanesi ara artifact'ı 1 gün, paketler 30 gün tutulur. Crashlytics
sembolleri artifact'a eklenmez.

Linux runner'da `godot` 4.7.2, `python3`, `clang` ve `lld` (`lld-link`) gerekir.
macOS runner'da Xcode, `godot` 4.7.2, SDKMAN (JDK `.sdkmanrc` ile zsh'te seçilir,
varsayılan JDK değişmez), `uv`, `python3`, `curl`, `shasum`, `zip` ve `unzip`
gerekir; Android SDK platform 35 ve NDK 28.1.13356709
`android-actions/setup-android` ile kurulur, CocoaPods yalnız Auth seçimlerinde
kilitli sürümle kurulur.
Runner'a ayrıca Node.js kurmak gerekmez; action'lar runner'ın kendi Node.js'iyle çalışır. SDK indirmeleri macOS runner'da
`../godot-firebase-third-party` altında kalıcı tutulur; godot-cpp nesneleri
SCons imzalarıyla seçimler arasında yeniden kullanılır. Fork PR'ları
self-hosted runner'larda çalışmaz.

Firebase C++/iOS, godot-cpp ve SCons sürümleri `tools/versions.env` içindedir.
GoogleSignIn kaynakları `tools/google_signin_ios/Podfile` ve lock dosyasında (kütüphaneye
bağlanan GoogleSignIn/AppAuth/GTMAppAuth/AppCheckCore git commit'ine pinli),
Android bridge bağımlılıkları `android/build.gradle` ve lock dosyasında,
oyun Maven/Kotlin/R8 seçimleri `addons/firebase/export/firebase_android_gradle.gd`
içinde sabitlenir. godot-cpp'nin 4.7 tag'i
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
