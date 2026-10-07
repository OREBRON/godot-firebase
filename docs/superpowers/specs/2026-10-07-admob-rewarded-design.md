# AdMob ödüllü reklam modülü — tasarım

Tarih: 2026-10-07. Kapsam kaynağı: kullanıcının oyunlarda ödüllü reklam izletip
oyuncuya karşılığında enerji kazandırma isteği. Bu belge tasarım taslağıdır;
üretim kodu ve cihazda çalışma iddiası içermez. Uygulama sırası
[AdMob uygulama planında](../plans/2026-10-07-admob-rewarded.md).

## Amaç ve sahiplik

SDK; ödüllü reklam yükleme/gösterme, reklam yaşam döngüsü olayları, ödül bildirimi,
reklam izni (UMP), sunucu doğrulaması (SSV) parametrelerinin iletimi ve AdMob'un
iOS/Android export yapılandırmasını sunar.

Oyun; enerji ekonomisini (miktar, üst sınır, günlük reklam limiti), ödülü veren
backend'i (SSV callback'ini doğrulayan Cloud Function), Firestore enerji kaydını
ve kurallarını sahiplenir. SDK enerji vermez, enerji alanı bilmez. Depo yalnız
`templates/` altında oyunun uyarlayacağı bir referans backend sunar.

AdMob App ID ve reklam birimi ID'leri oyuna aittir; reusable AAR/native binary'e
gömülmez. Export seçeneği ve oyun kodu üzerinden verilir.

## Global constraints

- Godot 4.7.2; Firebase C++ SDK 13.13.0; Firebase iOS SDK 12.19.1 pinleri değişmez.
- C++ SDK 13.13.0'da AdMob yoktur (`gma` 12.1.0'da kullanımdan kaldırıldı,
  13.0.0'da silindi). Firebase.zip 12.x de Google Mobile Ads içermez. Modül,
  Crashlytics gibi Android Java/JNI ve iOS Objective-C++ köprüleriyle yazılır.
- Yalnız iOS ve Android üretim hedefidir; editör/masaüstünde mock çalışır.
- GDScript API + mock + `FirebaseAdmobNative` aynı metot/default/sonuç/sinyal
  sözleşmesini paylaşır. Modül adı `admob`; sınıf adları addan türetilir
  (`FirebaseAdmob`, `FirebaseAdmobMock`, `FirebaseAdmobNative`), özel eşleme eklenmez.
- Modüller birbirine bağımlı değildir. Auth UID'sini SSV'ye vermek oyunun işidir.
- Geçersiz girdi native'e ulaşmadan `ERR_INVALID_ARGUMENT` olur; native aynı
  sınırı savunur. Mobilde eksik native sessizce mock'a düşmez.
- Firebase yanıtları gibi reklam callback'leri de yalnız `FirebaseModuleNative`
  üzerinden ana thread'e taşınarak yayılır.
- "SDK ödül bildirdi" ile "sunucu ödülü verdi" birbirinin yerine kullanılmaz.

## Bağımlılıklar

| Platform | Paket | Pin (2026-10-07) | Not |
|---|---|---|---|
| Android | Google Mobile Ads Next-Gen | `com.google.android.libraries.ads.mobile.sdk:ads-mobile-sdk:1.5.0` (yedek: Legacy `play-services-ads:25.5.0`) | minSdk 24, compileSdk ≥ 35 |
| Android | UMP | `com.google.android.ump:user-messaging-platform:4.0.0` | Reklam SDK'sı geçişli getirir; köprü derlemesi için açık pin |
| iOS | GoogleMobileAds | 13.11.0, SPM xcframework zip + SHA-256 | Statik; iOS ≥ 13; Xcode ≥ 26.2 |
| iOS | GoogleUserMessagingPlatform | 3.1.0, SPM xcframework zip + SHA-256 | Statik |

- Godot 4.7.2 şablonu (AGP 8.6.1, compileSdk 36, minSdk 24, Kotlin 2.1.21;
  eklentinin yönettiği Kotlin 2.4.0) bu gereksinimleri karşılar.
- POM analizine göre reklam SDK'sının istediği Play Services/measurement sürümleri
  mevcut `firebase-analytics:23.2.0` ve `play-services-base:18.10.1` ile çakışmaz.
  Gerçek Gradle çözümlemesi ve lock/verification güncellemesi planın ilk görevidir.
- iOS paketleri bootstrap'ta sürümlü URL ve SHA-256 ile indirilir (Firebase.zip
  gibi); CocoaPods gerekmez. Statik framework'ler mevcut `link_static_framework`
  yoluyla eklentinin kütüphanesine bağlanır; `*.bundle` gizlilik kaynakları
  mevcut `resources/` akışıyla export'a eklenir.
- Self-hosted macOS runner'ında Xcode ≥ 26.2 gerekir. Değilse daha eski bir
  GoogleMobileAds 13.x pinlenir; bu, plan görevi ADM-0'da kesinleşir.

## Yaklaşım

```
GDScript (FirebaseAdmob) ── FirebaseRequests ── FirebaseAdmobNative (C++)
                                                  │  token → Completion haritası
                                                  │  ad_id → reklam durumu
                                     ┌────────────┴────────────┐
                    Android: FirebaseAdmobBridge.java    iOS: admob_ios.mm
                    (activity.runOnUiThread, JNI)        (main queue, top VC)
```

- Crashlytics köprü düzeni izlenir: C++ token ayırır, işlemi platforma iletir;
  platform tamamlanınca token'ı bir kez tüketir. Reklam olayları ayrıca
  `ad_event` sinyaliyle ana thread'e taşınır.
- Reklam nesneleri platform tarafında `ad_id` ile tutulur; `ad_id` C++'ta üretilir.
- UMP, C++ SDK'nın `firebase::ump` modülü yerine aynı köprülerde yazılır. C++
  `ump` iOS'ta UMP 2.3.0'a karşı derlenmiştir; GoogleMobileAds 13.11 ile birlikte
  UMP 3.1.0 bağlamak doğrulanmamıştır. Ayrıca ek C++ arşivi ve Java yardımcısı
  getirir. Köprüler zaten gerekli olduğundan tek mekanizma tercih edildi.
- Reklam SDK'sı ilk `load_rewarded` çağrısında başlatılır. Ayrı bir başlatma
  çağrısı gerekmez; Google'ın önerdiği gibi başlatma izin kontrolünden sonradır.

## Public API

`Firebase.admob` / `FirebaseAdmob`:

```gdscript
## İzin (UMP). Her açılışta reklam istemeden önce çağrılır.
request_consent(options: Dictionary = {}) -> FirebaseTask
show_privacy_options() -> FirebaseTask
reset_consent() -> FirebaseTask   # yalnız test

## İstek yapılandırması (isteğe bağlı, ilk yüklemeden önce)
set_request_configuration(config: Dictionary) -> FirebaseTask

## Ödüllü reklam
load_rewarded(ad_unit_id: String) -> FirebaseTask
show_rewarded(ad_id: int, verification: Dictionary = {}) -> FirebaseTask
release_rewarded(ad_id: int) -> void

signal ad_event(ad_id: int, event: String)

static func test_rewarded_ad_unit() -> String
```

- `request_consent` UMP bilgisini günceller, gerekiyorsa formu gösterir. Sonuç
  `{can_request_ads: bool, consent_status: String, privacy_options_required: bool}`;
  `consent_status` `unknown|required|not_required|obtained`.
  `options` yalnız test içindir: `{debug_geography: "eea"|"other"|"regulated_us_state", test_device_hashed_ids: PackedStringArray}`.
- `show_privacy_options` aynı sonucu döner. `privacy_options_required` true ise
  oyunun ayarlar ekranında bu butonu göstermesi zorunludur (Google politikası).
- `set_request_configuration` anahtarları: `test_device_ids: PackedStringArray`,
  `max_ad_content_rating: "G"|"PG"|"T"|"MA"`, `child_directed: bool`,
  `under_age_of_consent: bool`. Verilmeyen anahtar SDK varsayılanında kalır.
- `load_rewarded` sonucu yeni `ad_id`'dir. Ad unit ID `ca-app-pub-<16 rakam>/<10 rakam>`
  biçiminde olmalıdır. Bu açılışta `request_consent` başarıyla tamamlanmadıysa ya
  da `can_request_ads` false ise `ERR_UNAVAILABLE` ile reddedilir. Yüklenen
  reklamın ömrü 1 saattir.
- `show_rewarded` reklam kapanınca biter; sonuç
  `{rewarded: bool, reward_type: String, reward_amount: int}`. Bir `ad_id` bir kez
  gösterilir; sonra serbest kalır. `verification` = `{user_id: String, custom_data: String}`
  SSV'ye iletilir ve gösterimden önce reklama atanır.
- `ad_event` olayları: `opened`, `impression`, `clicked`, `reward_earned`, `closed`,
  `failed_to_show`. Google reklamlarında `reward_earned` `closed`'dan önce gelir;
  mediation kaynaklarında sıra değişebilir, bu yüzden nihai sonuç task'tadır.
- `test_rewarded_ad_unit()` Google'ın resmi test birimini platforma göre döner
  (Android `ca-app-pub-3940256099942544/5224354917`, iOS `ca-app-pub-3940256099942544/1712485313`).
  Geliştirmede gerçek birim kullanmak AdMob hesabının askıya alınmasına yol açabilir.

### Backend sözleşmesi

Mock (`FirebaseAdmobMock`) ve native (`FirebaseAdmobNative`) aynı metotları sunar.
`int` dönenler istek kimliğidir; sonuç `request_completed` ile gelir.

```gdscript
initialize() -> int                                         # Error
request_consent(options: Dictionary) -> int                 # sonuç: consent sözlüğü
show_privacy_options() -> int                               # sonuç: consent sözlüğü
reset_consent() -> int                                      # sonuç: null
set_request_configuration(config: Dictionary) -> int        # sonuç: null
load_rewarded(ad_unit_id: String) -> int                    # sonuç: ad_id (int > 0)
show_rewarded(ad_id: int, verification: Dictionary) -> int  # sonuç: ödül sözlüğü
release_rewarded(ad_id: int) -> void
signal ad_event(ad_id: int, event: String)
```

Kurallar:
- **Girdi doğrulaması** API'dedir; backend aynı kuralları savunma amaçlı tekrarlar.
  - Ad unit: `^ca-app-pub-\d{16}/\d{10}$`.
  - `ad_id > 0`.
  - `verification` yalnız String `user_id`/`custom_data` içerir.
  - `options` yalnız `debug_geography` (`eea|other|regulated_us_state`) ve String
    dizisi `test_device_hashed_ids` içerir.
  - `config` yalnız tasarımdaki dört anahtarı içerir.
- **İzin durumu backend'dedir.** Bu açılışta `request_consent` tamamlanmadan ya da
  `can_request_ads` false iken `load_rewarded` `ERR_UNAVAILABLE` döner.
- **Reklam tüketimi:** Gösterilen veya bırakılan `ad_id` unutulur. Tekrar
  kullanımı `ERR_INVALID_ARGUMENT` (bilinmeyen reklam) döner. Yüklemeden 1 saat
  sonra gösterim `ERROR_AD_EXPIRED` ile biter ve reklam bırakılır.
- **Tek tam ekran kuralı:** Açık bir reklam veya izin formu varken ikinci gösterim
  ya da form isteği `ERR_BUSY` döner.

### Hata sözleşmesi

- Eklenti kodları: `ERR_INVALID_ARGUMENT` (biçim, bilinmeyen `ad_id`),
  `ERR_UNAVAILABLE` (native yok, izin alınmadı), `ERR_BUSY` (başka tam ekran reklam
  veya izin formu açık), `ERR_CANCELLED` (kapatma sırasında bekleyen işlem).
- Android ve iOS reklam hata kodları farklıdır. Köprüler bunları `FirebaseAdmob`
  sabitlerine çevirir: `ERROR_INTERNAL=1`, `ERROR_INVALID_REQUEST=2`,
  `ERROR_NETWORK=3`, `ERROR_NO_FILL=4`, `ERROR_APP_ID_MISSING=5`,
  `ERROR_AD_EXPIRED=6`, `ERROR_AD_ALREADY_USED=7`, `ERROR_SHOW_FAILED=8`.
  Platform kodu ve mesajı `error_message` içinde korunur.

## Enerji akışı (oyun tarafı)

Onaylanan yol sunucu doğrulamasıdır (Karar 2):

1. Oyun açılışta `request_consent()`, sonra seviye başında `load_rewarded(unit)` çağırır.
2. Oyuncu "Reklam izle +5 enerji"ye basar:
   `show_rewarded(ad, {user_id: auth_uid, custom_data: "energy"})`.
3. Google ödülü SSV callback URL'ine imzalı GET isteğiyle bildirir. Cloud Function:
   - imzayı `https://www.gstatic.com/admob/reward/verifier-keys.json` anahtarlarıyla
     ECDSA P-256/SHA-256 olarak doğrular (anahtarlar en fazla 24 saat önbelleklenir;
     imzalanan kısım sorgunun `&signature=` öncesidir),
   - `ad_unit` ve `custom_data` izinli listede mi bakar,
   - `ad_rewards/{transaction_id}` belgesiyle idempotent çalışır,
   - aynı transaction'da `users/{user_id}.energy` alanını üst sınıra kadar artırır,
   - 200 döner (Google 200 dışında 1 sn arayla 5 kez tekrar dener).
4. Oyun `listen_doc("users/<uid>")` ile enerjiyi gösterir. Task
   `rewarded: true` döndüğünde "ödül işleniyor" gösterilir; SSV gecikebilir.
5. Firestore kuralları istemcinin `energy` ve `ad_rewards` yazmasını engeller.

Basit alternatif istemci tarafı vermedir: `rewarded: true` olunca oyun kendisi
enerji ekler. Bu, değiştirilmiş istemciyle reklam izlemeden enerji alınabileceği
anlamına gelir; çevrimiçi ekonomi için önerilmez.

Editörde SSV callback'i gelmez. Referans örnek, `Firebase.is_mock("admob")`
iken `ad_event` `reward_earned` olayında Firestore mock'una aynı artışı yazan
yalnız-editör bir simülatör içerir; bu kod oyunun debug koduna aittir.

## Mock

- `load_rewarded` sonraki karede yeni `ad_id` ile başarılı olur.
  Test yardımcıları: `fail_next`, `simulate_no_fill()`.
- `show_rewarded` olayları sırayla ayrı karelerde yayar: `opened`, `impression`,
  `reward_earned`, `closed`. Ardından sonucu döner. `close_next_early()` ödülsüz
  kapanmayı taklit eder; `set_mock_reward(type, amount)` ödülü belirler.
  Son `verification` sözlüğü testte okunabilir.
- `request_consent`: `firebase/admob/mock_consent` proje ayarı `not_required`
  (varsayılan) veya `required`. `required` iken ilk çağrı formu "gösterip"
  `obtained` döner, `privacy_options_required` true olur. Böylece AB akışı editörde
  denenebilir.
- Süre aşımı, tekrar kullanım ve meşgul kuralları native ile aynı kodları üretir.

## Export yapılandırması

Android export eklentisi:
- Yeni seçenek `firebase/admob_app_id`. `bin/modules.txt` `admob` içeriyorsa zorunludur
  ve `ca-app-pub-<16>~<10>` biçiminde olmalıdır. Eksik App ID uygulamayı açılışta
  çökerttiği için export hatası verilir.
- `_get_android_manifest_application_element_contents` içine
  `com.google.android.gms.ads.APPLICATION_ID` meta-data'sı eklenir.
- `DEPENDENCIES["admob"]` reklam SDK'sını ve UMP'yi ekler. ProGuard: köprü sınıfı
  korunur; `com.google.android.gms.ads.**` / `com.google.android.libraries.ads.**`
  / `com.google.android.ump.**` için kapsamlı `-dontwarn`.

iOS export eklentisi:
- `firebase/admob_app_id` → `GADApplicationIdentifier`. Eksik ise uygulama
  çöker; export hatası verilir.
- `SKAdNetworkItems` en az Google kimliği `cstr6suwn9.skadnetwork` ile eklenir.
  Google'ın 50 kimlikli listesi makinece okunur yayınlanmadığından oyun gerekirse
  `application/additional_plist_content` ile tam listeyi verir. Var olan anahtar,
  mevcut plist çakışma kontrolüyle korunur.
- `firebase/admob_tracking_description` doluysa `NSUserTrackingUsageDescription`
  eklenir; UMP IDFA mesajı yapılandırıldıysa ATT istemini UMP gösterir. Ayrı bir
  ATT API'si eklenmez.

## Yaşam döngüsü ve thread'ler

- Android: Godot çağrıları render thread'indedir. Köprü yükleme/göstermeyi
  `activity.runOnUiThread` ile yapar; callback'ler token'ı tüketir ve `ad_event`'i
  ana thread'e taşır. Tam ekran reklam sırasında Godot activity `onPause` alır:
  ses durur, oyun döngüsü ve zamanlayıcılar çalışmaya devam eder.
- iOS: SDK çağrıları main queue'dadır. Godot 4.7.2 SwiftUI host kullandığı için
  sunum, `platform_credentials_ios.mm` içindeki `top_view_controller()` ile
  bulunan en üst ekrandan yapılır. Modal sunum uygulamayı arka plana almaz.
- Bu yüzden oyun `opened` olayında kendini duraklatıp sesi kısar, `closed`
  olayında devam eder. README örneği bunu gösterir.
- Aynı anda tek tam ekran içerik (reklam veya izin formu) açık olabilir;
  ikincisi `ERR_BUSY` döner.
- `shutdown_all` bekleyen task'ları `ERR_CANCELLED` ile bitirir, platform
  reklamlarını bırakır ve geç gelen callback'leri yok sayar.

## Kayıt noktaları

AGENTS.md düzenine göre `admob` şu yerlere eklenir:
- `addons/firebase/core/firebase.gd` `MODULES` ve `admob` özelliği,
- `SConstruct` `MODULES` (C++ arşivi yok; iOS framework klasörü ve sistem
  framework'leri),
- `src/register_types.cpp` (kayıt + `shutdown_all`),
- `tools/bootstrap.sh` / `tools/versions.env` (iOS zip pinleri),
- `tools/build_android_aar.sh` (keep/dontwarn) ve `android/build.gradle` + lock
  + verification metadata,
- `addons/firebase/export/firebase_android_gradle.gd` `DEPENDENCIES`,
- `tests/test_sdk_capability_packages.py`, `.github/workflows/sdk-capabilities.yml`
  seçim matrisi, README modül tablosu ve AGENTS.md ürün sayısı.

`package.sh` "bütün kurulu modüller" seçimini `godot-firebase-sdk-capabilities.zip`
olarak adlandırır; dokuzuncu modülle bu adın kapsamı değişir. Release seçimine
(`build.yml` `MODULE_SELECTION`) `admob` yalnız cihaz kabulünden sonra eklenir.

## Doğrulama ve kabul

- Yerel: mock testleri, export testleri (App ID doğrulaması, manifest/plist
  içeriği, çakışma), backend sözleşme eşleşmesi, AAR testi, iOS/Android native CI derlemesi.
- Cihaz (Android + iPhone), test birimleriyle:
  - yükle/göster/ödül,
  - erken kapatmada ödül yok,
  - süresi geçmiş reklam hatası,
  - EEA debug coğrafyasında izin formu ve gizlilik seçenekleri,
  - iOS'ta UMP IDFA/ATT akışı,
  - reklam sırasında duraklatma/ses davranışı,
  - SSV callback'inin test anahtarlarıyla fonksiyona ulaşması ve tek kez enerji vermesi.
- iOS'ta gerçek Google reklamları uygulama App Store'da listelenene kadar
  sunulmaz; test reklamları bu sınırdan etkilenmez.
- Mock ve masaüstü sonuçları cihaz kabulünün yerine geçmez.

## Kapsam dışı

Banner, interstitial, app open ve native reklamlar; mediation; gelir (paid event)
raporlaması; ayrı ATT API'si; oyun ekonomisinin SDK'ya taşınması. Bunlar ayrı
istekle ele alınır. Tasarım tek formatla başlar; `ad_event` ve hata sözleşmesi
ileride başka formatlara genişleyebilir.

## Kararlar

Kullanıcı 2026-10-07'de onayladı:

1. **Android SDK: Next-Gen** `com.google.android.libraries.ads.mobile.sdk:ads-mobile-sdk:1.5.0`.
   - Legacy `play-services-ads` bakım modundadır: 2027-06-30'da kullanımdan
     kalkar, 2028-06-30'da kapanır.
   - ADM-0 spike'ı Next-Gen'in Java köprüsünden kullanımını, SSV'yi, UMP ile
     birlikteliğini ve R8'i doğrular. Biri bloklanırsa Legacy 25.5.0'a dönülür
     ve bu belge güncellenir.
   - iOS'ta tek SDK vardır.
2. **Ödül verme: SSV + Cloud Function.** İstemci tarafı verme desteklenmez;
   `rewarded: true` yalnız arayüz geri bildirimi içindir.
3. **UMP ilk sürümde dahil.**
4. **Formatlar: yalnız ödüllü reklam.**

## Birincil kaynaklar

- Android: [quick-start](https://developers.google.com/admob/android/quick-start),
  [rewarded](https://developers.google.com/admob/android/rewarded),
  [Legacy deprecation](https://developers.google.com/admob/android/deprecation),
  [Next-Gen quick-start](https://developers.google.com/admob/android/next-gen/quick-start),
  [Next-Gen rewarded](https://developers.google.com/admob/android/next-gen/rewarded),
  [test ads](https://developers.google.com/admob/android/test-ads),
  [privacy](https://developers.google.com/admob/android/privacy),
  [SSV](https://developers.google.com/admob/android/ssv).
- iOS: [quick-start](https://developers.google.com/admob/ios/quick-start),
  [rewarded](https://developers.google.com/admob/ios/rewarded),
  [SKAdNetwork](https://developers.google.com/admob/ios/3p-skadnetworks),
  [IDFA/ATT](https://developers.google.com/admob/ios/privacy/idfa),
  [SPM paketi](https://github.com/googleads/swift-package-manager-google-mobile-ads).
- [C++ `ump` başlığı](https://github.com/firebase/firebase-cpp-sdk/blob/v13.13.0/ump/src/include/firebase/ump/consent_info.h),
  [Firebase iOS release notes](https://firebase.google.com/support/release-notes/ios),
  [Godot 4.7.2 config.gradle](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/java/app/config.gradle).

Sürüm numaraları 2026-10-07 tarihlidir; uygulamada pin ve SHA'lar ADM-0'da
yeniden doğrulanıp `tools/versions.env` ile export bağımlılıklarına yazılır.
