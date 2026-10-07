# AdMob Rewarded Ads Implementation Plan

**Goal:** iOS/Android oyunlarında ödüllü reklam izletmek ve ödülü (ör. enerji)
sunucu doğrulamasıyla vermek; editörde aynı akışı mock ile geliştirmek.

**Architecture:** Yeni `admob` modülü mevcut GDScript API/mock/native düzenine
eklenir. C++ SDK'da AdMob olmadığından Crashlytics gibi Android Java/JNI ve iOS
Objective-C++ köprüleri kullanılır; UMP izni aynı köprülerdedir. Enerji ekonomisi
oyuna aittir; depo yalnız referans SSV backend'i sunar.

**Tech Stack:** Godot 4.7.2, GDScript, C++/GDExtension, Android Java/JNI,
iOS Objective-C++, Google Mobile Ads (Android Next-Gen 1.5.0, yedek Legacy 25.5.0;
iOS 13.11.0), UMP (Android 4.0.0, iOS 3.1.0), Cloud Functions (referans şablon).

**Spec:** [AdMob ödüllü reklam tasarımı](../specs/2026-10-07-admob-rewarded-design.md)

## Uygulama durumu — 2026-10-08

ADM-0…ADM-7 `feat/admob-rewarded` dalında görev başına commit edildi. Dört karar
2026-10-07'de onaylandı: Next-Gen Android SDK, SSV ile ödül, UMP dahil, yalnız
ödüllü format. Spike sonucu yapılandırma `age_restricted_treatment` anahtarına geçti.

Yerelde (Linux) doğrulananlar:
- GDScript ve Python testleri,
- `tests/test_android_aar.sh`,
- `javac --release 8` köprü derlemesi,
- NDK 28.2 ile `admob` dahil Android arm64 derlemesi ve bağlaması,
- SSV şablon testleri (`node --test`, Firestore Emulator kuralları).

Bekleyenler:
- iOS köprüsünün derlenmesi ve bağlanması (macOS CI),
- ADM-8 cihaz kabulü.

Kanıtlar [AdMob doğrulama kaydında](../../verification/admob.md).
İşaretli adımlar yalnız yapılan adımı gösterir; cihaz kabulü değildir.

## Global Constraints

- Godot 4.7.2, Firebase C++ 13.13.0 ve Firebase iOS 12.19.1 pinleri değişmez.
- API, mock ve native aynı metot/default/sonuç/sinyal sözleşmesini paylaşır;
  `tests/test_backend_contracts.gd` bunu yakalar.
- Oyun App ID'si, reklam birimi ID'si ve SSV URL'i reusable AAR/binary'e girmez.
- Geliştirme ve testte yalnız Google test birimleri ya da kayıtlı test cihazları kullanılır.
- Ortak dosyalara (`firebase.gd`, `SConstruct`, `register_types.cpp`, `bootstrap.sh`,
  export eklentileri, workflow'lar) iki görev aynı anda dokunmaz; koordinatör
  sırayla entegre eder.
- Her görev: önce başarısız test, sonra uygulama, tam test paketi, dar diff
  incelemesi ve görev başına ayrı commit.

## Review Focus

- **Ödül iki kez veya hiç verilmez:** SSV `transaction_id` idempotensi,
  `reward_earned`/`closed` sırası, erken kapatma.
- **Uygulama açılışta çöker:** App ID eksik/yanlış iken export'un durması
  (Android manifest, iOS plist).
- **Asılı task:** gösterim başarısız, reklam süresi geçmiş, `shutdown_all`,
  ikinci tam ekran isteği (`ERR_BUSY`).
- **İzinsiz istek:** bu açılışta `request_consent` olmadan `load_rewarded`'ın reddedilmesi.
- **Thread:** Android'de UI thread dışında SDK çağrısı ve iOS'ta main queue dışında
  çağrı olmaması.

## Çalışma sırası

```
ADM-0 bağımlılık spike ──┬─> ADM-4 Android köprüsü ─┐
ADM-1 API + mock ── ADM-3 native çekirdek ──┤        ├─> ADM-6 kayıt/paket/CI ─> ADM-8 cihaz kabulü
ADM-2 export yapılandırması ──────────────┴─> ADM-5 iOS köprüsü ─┘
ADM-7 SSV referans backend (bağımsız) ─────────────────────────────────────> ADM-8
```

- İlk dalga paralel: ADM-0, ADM-1, ADM-2, ADM-7.
- ADM-4 ve ADM-5 farklı platform dosyalarında paralel ilerler; ortak C++ ADM-3'tedir.

Ortak kontroller:

```bash
GODOT=godot python3 tools/run_tests.py
ANDROID_HOME=<sdk> bash tests/test_android_aar.sh
tools/build.sh --modules auth,firestore,functions,admob --platforms ios,android
```

---

### ADM-0: Bağımlılık spike'ı ve pinler

**Dependencies:** Bağımsız. **Files:** `tools/versions.env`,
`android/build.gradle`, `android/gradle.lockfile`,
`android/gradle/verification-metadata.xml`, `tools/bootstrap.sh`, ölçüm notu için
`docs/verification/admob.md` (**yapılacak**).

- [x] **Step 1 — Ortam:**
  - Self-hosted runner'da Xcode sürümünü kaydet; GoogleMobileAds 13.11.0 en az 26.2 ister.
  - Uymuyorsa runner'ın Xcode'una uyan en yeni 13.x'i seç ve gerekçesini yaz.
- [x] **Step 2 — Android çözümleme:**
  - `bridgeCompile`'a seçilen reklam SDK'sı ve UMP 4.0.0'ı ekle.
  - Gradle lock ve verification metadata'yı güncelle.
  - `firebase-analytics:23.2.0`/`play-services-base:18.10.1` ile birlikte gerçek
    çözümlemenin çakışmasız olduğunu kaydet.
- [x] **Step 3 — Next-Gen spike:** `javac --release 8` ile
  derlenen küçük bir köprü örneği şunları kullanabilmeli:
  - başlatma (App ID kodla verilir),
  - ödüllü yükleme/gösterme,
  - SSV seçenekleri,
  - UMP ile birlikte kullanım.

  R8 kurallarını ve AAR boyutunu ölç. Herhangi biri bloklanırsa Legacy 25.5.0'a geç ve tasarıma not düş.
- [x] **Step 4 — iOS pinleri:**
  - GoogleMobileAds 13.11.0 ve UMP 3.1.0 için sürümlü SPM zip URL'lerini ve
    SHA-256 değerlerini `versions.env`'e yaz.
  - `bootstrap.sh`, Firebase.zip ile aynı `fetch_zip` desenini kullanır.
- [x] **Step 5 — Doğrulama ve teslim:**
  - `tests/test_android_aar.sh` ve bootstrap tekrar çalıştırması (`.complete` atlaması) geçer.
  - Ölçümler `docs/verification/admob.md`'ye yazılır; görev ayrı commit olur.

### ADM-1: GDScript API ve mock

**Dependencies:** Bağımsız. **Files:** `addons/firebase/admob/firebase_admob.gd`,
`addons/firebase/admob/firebase_admob_mock.gd` (**yapılacak**),
`addons/firebase/core/firebase.gd` (`MODULES` + `admob` özelliği),
`tests/test_admob_mock.gd`, `tests/test_admob_consent_mock.gd` (**yapılacak**).

**Interfaces:** Tasarımdaki Public API, `ad_event` sinyali, `FirebaseAdmob.ERROR_*`
sabitleri ve `test_rewarded_ad_unit()`.

- [x] **Step 1 — Testler:**
  - yükle→göster→`{rewarded: true}` ve olay sırası `opened, impression, reward_earned, closed`,
  - erken kapatmada `rewarded: false`,
  - gösterilen reklamı tekrar göstermede `ERR_INVALID_ARGUMENT`,
  - 1 saati geçen reklamda `ERROR_AD_EXPIRED`,
  - eşzamanlı gösterimde `ERR_BUSY`,
  - geçersiz ad unit biçiminde backend çağrılmadan `ERR_INVALID_ARGUMENT`,
  - `request_consent` öncesi `load_rewarded` için `ERR_UNAVAILABLE`,
  - `firebase/admob/mock_consent=required` ile form→`obtained` ve
    `privacy_options_required`,
  - `verification` sözlüğünün mock'ta kaydedilmesi,
  - `release_rewarded` sonrası bilinmeyen `ad_id`.
- [x] **Step 2 — İlk kontrol:** Testler modül yokken başarısız olmalı.
- [x] **Step 3 — Uygulama:**
  - Doğrulama API'de; mock aynı kodları üretir.
  - Olaylar ayrı karelerde `call_deferred` ile yayılır.
  - Mock yardımcıları (`simulate_no_fill`, `close_next_early`, `set_mock_reward`)
    yalnız mock'tadır.
  - `firebase.gd` `MODULES` listesine `admob` eklenir.
- [x] **Step 4 — Doğrulama:**
  - Tam GDScript paketi geçer.
  - `test_modules.gd` dokuz modülü görür.
  - `test_backend_contracts.gd`, native olmadığında mock'u atlar (mevcut davranış).
- [x] **Step 5 — Review ve teslim:** API sözleşmesi tasarımla birebir mi
  incelenir; ayrı commit.

### ADM-2: Export yapılandırması

**Dependencies:** Bağımsız (`modules.txt` okuması mevcut).
**Files:** `addons/firebase/export/firebase_android_export_plugin.gd`,
`addons/firebase/export/firebase_android_gradle.gd`,
`addons/firebase/export/firebase_ios_export_plugin.gd`,
`tests/test_android_export.gd`, `tests/test_ios_export.gd`.

- [x] **Step 1 — Testler:**
  - Android:
    - `admob` seçiliyken App ID boş veya biçimsizse export hatası,
    - geçerli ID'de manifest meta-data'sı,
    - `admob` yokken hiçbir şey eklenmez,
    - `dependencies_for(["admob"])` reklam SDK'sını ve UMP'yi içerir.
  - iOS:
    - `GADApplicationIdentifier` eklenir,
    - `SKAdNetworkItems` en az `cstr6suwn9.skadnetwork` içerir; ek plist'te
      liste varsa korunur ve Google kimliği eksikse hata verilir,
    - `NSUserTrackingUsageDescription` yalnız seçenek doluysa eklenir,
    - ek plist'teki çakışan değerler reddedilir.
- [x] **Step 2 — İlk kontrol:** Yeni testler mevcut eklentide başarısız olmalı.
- [x] **Step 3 — Uygulama:**
  - Seçenekler `firebase/admob_app_id` ve `firebase/admob_tracking_description`.
  - Mevcut `_additional_plist_values` çakışma kontrolü yeniden kullanılır.
  - Android `METADATA` akışı değil, App ID'ye özel doğrulanmış meta-data üretilir.
- [ ] **Step 4 — Doğrulama:**
  - Tam paket geçer; export testleri hem `--script` hem `--editor --script` modunda koşar.
  - `tools/test_android_export.py` sentetik APK'sı `admob` seçimiyle derlenir
    (Android SDK gerektirir).
- [x] **Step 5 — Review ve teslim:** Ayrı commit.

### ADM-3: Native çekirdek

**Dependencies:** ADM-1 sözleşmesi. **Files:** `src/admob/firebase_admob_native.*`,
`src/admob/platform/admob_platform.h` (**yapılacak**), `src/register_types.cpp`,
`SConstruct` (`MODULES["admob"]`), `tests/test_native_shutdown.py`.

**Interfaces:** `FirebaseAdmobNative` bound metotları ve `ad_event` sinyali
ADM-1 ile aynı. Platform arayüzü:
- `initialize_admob_platform()`
- `dispatch_admob(operation, payload, token)`
- `finish_admob_request(token, Outcome)`
- `emit_admob_event(ad_id, event)`

- [x] **Step 1 — Testler:**
  - `test_native_shutdown.py` `admob`'un App silinmeden kapatıldığını bekler.
  - Sözleşme testi `FirebaseAdmobNative` imzalarını mock ile karşılaştırır
    (mobil koşuda).
- [x] **Step 2 — İlk kontrol:** Shutdown testi başarısız olmalı.
- [x] **Step 3 — Uygulama:**
  - Token→Completion haritası ve `ad_id`→nesne (instance) haritası kurulur.
  - Native doğrulama GDScript ile aynı sınırları uygular.
  - Tek tam ekran kilidi ve `shutdown_all` bekleyenleri `ERR_CANCELLED` ile bitirir.
  - Geç callback'ler yok sayılır.
  - `SConstruct`'ta C++ arşivi yoktur; platform kaynakları Crashlytics gibi seçilir.
- [ ] **Step 4 — Doğrulama:** Python testleri ve iOS/Android native derlemesi
  (platform dosyaları ADM-4/5 gelene kadar derleme dışı kalır).
- [x] **Step 5 — Review ve teslim:** Ayrı commit.

### ADM-4: Android köprüsü (reklam + UMP)

**Dependencies:** ADM-0, ADM-3.
**Files:** `android/src/org/godotengine/godotfirebase/FirebaseAdmobBridge.java`,
`src/admob/platform/admob_android.cpp` (**yapılacak**), `tools/build_android_aar.sh`.

- [x] **Step 1 — Testler:**
  - `tests/test_android_aar.sh` köprü sınıfının AAR'da ve `proguard.txt` keep
    kuralında olduğunu doğrular.
  - Native derleme `admob` seçimiyle geçer.
- [x] **Step 2 — İlk kontrol:** AAR testi köprü yokken başarısız olmalı.
- [x] **Step 3 — Uygulama:**
  - Bütün SDK çağrıları `activity.runOnUiThread` içindedir.
  - SDK başlatma tek seferliktir; reklamlar `HashMap<Long, Ad>` içinde tutulur.
  - SSV seçenekleri gösterimden önce atanır.
  - Platform hata kodları `ERROR_*` sabitlerine eşlenir; olaylar `nativeEvent` ile iletilir.
  - UMP:
    - `requestConsentInfoUpdate` + `loadAndShowConsentFormIfRequired`,
    - `showPrivacyOptionsForm`, `reset`,
    - debug ayarları yalnız `request_consent` seçeneklerinden gelir.
  - JNI tarafı Crashlytics'teki `JniContext` desenini paylaşır; kopyalamak yerine
    ortak yardımcıya taşınması ayrıca değerlendirilir.
- [x] **Step 4 — Doğrulama:**
  - AAR testi ve Android native derlemesi geçer.
  - R8'li sentetik APK (`tools/test_android_export.py`) derlenir.
- [x] **Step 5 — Review ve teslim:** Ayrı commit.

### ADM-5: iOS köprüsü (reklam + UMP)

**Dependencies:** ADM-0, ADM-3. **Files:** `src/admob/platform/admob_ios.mm`
(**yapılacak**), `SConstruct` (framework klasörleri, `AppTrackingTransparency`
ve GMA'nın istediği sistem framework'leri).

- [ ] **Step 1 — Testler:**
  - iOS cihaz ve simulator native derlemesi `admob` seçimiyle geçer.
  - `build/ios/resource_bundles.txt` GMA/UMP gizlilik bundle'larını içerir.
- [ ] **Step 2 — İlk kontrol:** Derleme köprü yokken bağlantı hatası vermeli.
- [x] **Step 3 — Uygulama:**
  - Bütün çağrılar `dispatch_async(dispatch_get_main_queue(), …)` içindedir.
  - Sunum, `platform_credentials_ios.mm` içindeki `top_view_controller()` ile
    yapılır; ortak yardımcıya taşınır.
  - `GADRewardedAd` `NSMutableDictionary` içinde tutulur; `fullScreenContentDelegate`
    olayları iletir.
  - `GADServerSideVerificationOptions` gösterimden önce atanır.
  - UMP `UMPConsentInformation`/`UMPConsentForm` main thread'de çağrılır.
- [ ] **Step 4 — Doğrulama:** Simulator derlemesi ve full seçim derlemesi geçer.
- [x] **Step 5 — Review ve teslim:** Ayrı commit.

### ADM-6: Kayıt, paketleme, CI ve doküman

**Dependencies:** ADM-2…ADM-5.
**Files:** `tests/test_sdk_capability_packages.py`, `tools/package.sh`,
`.github/workflows/sdk-capabilities.yml`, `README.md`, `AGENTS.md`,
`docs/verification/sdk-capabilities.md`.

- [x] **Step 1 — Testler:** Paket testi `admob` tekil ZIP'ini
  (`godot-firebase-admob.zip`) ve dokuz modüllü seçimi bekler.
- [x] **Step 2 — İlk kontrol:** Testler başarısız olmalı.
- [x] **Step 3 — Uygulama:**
  - CI seçim matrisine `admob` eklenir.
  - README'ye modül tablosu, kurulum (App ID, test birimleri, izin ve pause örneği)
    ve SSV akışı yazılır.
  - AGENTS.md ürün sayısı ve kayıt listesi güncellenir.
  - `godot-firebase-sdk-capabilities.zip` adının dokuz modüle genişlediği belgelenir.
- [ ] **Step 4 — Doğrulama:** Python testleri, tam GDScript paketi ve CI geliştirme
  build'leri geçer.
- [ ] **Step 5 — Review ve teslim:** Ayrı commit.
  - Release `MODULE_SELECTION`'a `admob` ADM-8 kabulünden sonra eklenir.

### ADM-7: SSV referans backend'i ve enerji örneği

**Dependencies:** Bağımsız (Karar 2 onaylandı). **Files:** `templates/admob_ssv/` (**yapılacak**):
- Cloud Function (TypeScript) ve birim testleri,
- `firestore.rules` örneği,
- `examples/rewarded_ads.gd` (istemci akışı + yalnız-editör SSV simülatörü).

- [x] **Step 1 — Testler:**
  - Kendi ürettiğimiz P-256 anahtarıyla imzalanmış sorgu kabul edilir.
  - Değiştirilmiş parametre, yanlış `ad_unit` veya `custom_data` reddedilir.
  - Aynı `transaction_id` ikinci kez enerji vermez.
  - Üst sınır aşılmaz.
  - Kurallar, istemcinin `energy` ve `ad_rewards` yazmasını reddeder (Emulator).
- [x] **Step 2 — İlk kontrol:** Testler şablon yokken başarısız olmalı.
- [x] **Step 3 — Uygulama:**
  - İmzalanan kısım ham sorgunun `&signature=` öncesidir.
  - Anahtarlar `verifier-keys.json`'dan 24 saate kadar önbelleklenir; testte
    `verifier-keys-test.json` kullanılır.
  - Firestore transaction'ı `ad_rewards/{transaction_id}` ve
    `wallets/{uid}.<ödül>` artışını birlikte yazar. Ödül türleri (enerji, can,
    altın, …) `CONFIG.rewards`'tadır; `spendReward` bakiyeyi atomik harcar.
  - Şablon eklenti ZIP'ine girmez (mevcut `templates/` gibi).
- [x] **Step 4 — Doğrulama:** `npm test` + Firebase Emulator. Gerçek AdMob
  callback'i ADM-8'dedir.
- [x] **Step 5 — Review ve teslim:** Ayrı commit.

### ADM-8: Cihaz kabulü ve release

**Dependencies:** ADM-0…ADM-7.
**Files:** `docs/verification/admob.md`, `.github/workflows/build.yml`
(`MODULE_SELECTION`).

- [ ] **Android cihaz (test birimi):**
  - yükle/göster/ödül; erken kapatmada ödül yok,
  - 1 saat sonra süresi geçen reklam hatası,
  - EEA debug coğrafyasında form ve gizlilik seçenekleri,
  - reklam sırasında oyun döngüsü ve ses davranışı,
  - R8'li release APK.
- [ ] **iPhone (test birimi):**
  - aynı senaryolar, UMP IDFA→ATT akışı,
  - `top_view_controller` sunumu,
  - reklam kapanınca Godot ses oturumunun geri gelmesi.
- [ ] **SSV:** Test reklamıyla Google callback'i fonksiyona ulaşır, imza doğrulanır,
  enerji tam bir kez artar; oyun `listen_doc` ile görür.
- [ ] **Release:** Kanıt `docs/verification/admob.md`'ye yazılır. `admob` release
  seçimine eklenir; kullanıcı sürümü ve tag'i kendisi oluşturur.
