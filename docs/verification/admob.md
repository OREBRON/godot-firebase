# AdMob doğrulama kaydı

Kapsam: [AdMob tasarımı](../superpowers/specs/2026-10-07-admob-rewarded-design.md) ve
[uygulama planı](../superpowers/plans/2026-10-07-admob-rewarded.md). Bu belge ölçülen
ve çalıştırılan kanıtı kaydeder; cihaz kabulü (ADM-8) ayrıca tamamlanır.

## ADM-0 — bağımlılık pinleri (2026-10-08)

### Android

- `android/build.gradle` köprü derlemesine Next-Gen
  `com.google.android.libraries.ads.mobile.sdk:ads-mobile-sdk:1.5.0` ve
  `com.google.android.ump:user-messaging-platform:4.0.0` eklendi.
- Gradle 9.3.1 (JDK 21) `--write-locks --write-verification-metadata sha256`
  ile çözümlendi.
  - Mevcut Firebase/Play Services pinleriyle çakışma yok.
  - Yükselen geçişli sürümler: `kotlinx-coroutines-android` 1.6.4→1.9.0,
    `androidx.annotation` 1.8.1→1.8.2, `appcompat-resources` 1.2.0→1.4.1,
    `error_prone_annotations` 2.26.0→2.41.0.
  - `listenablefuture`, Guava'nın boş artefaktına çözülür.
- Yeni geçişli artefaktlar: 35 adet, R8 öncesi toplam 16,9 MB. En büyükleri:

  | Artefakt | Boyut |
  |---|---|
  | `ads-mobile-sdk` | 6,1 MB |
  | `tink-android` | 3,2 MB |
  | `guava` | 2,8 MB |
  | `work-runtime` | 1,5 MB |
  | `okhttp` | 0,8 MB |
  | `protobuf-javalite` | 0,7 MB |
  | `user-messaging-platform` | 0,4 MB |

  Cronet de gelir. APK'daki gerçek fark R8 sonrası export'ta ölçülür (ADM-8).
- Next-Gen spike'ı: `FirebaseAdmobBridge.java` `javac --release 8` ile uyarısız
  derlendi. Kapsadığı API'ler:
  - başlatma (`InitializationConfig`, App ID kodla),
  - `RewardedAd.load`/`show`, `ServerSideVerificationOptions(userId, customData)`,
    olay callback'leri,
  - `RequestConfiguration`,
  - UMP 4.0.0.
- Next-Gen 1.5.0 ve iOS 13.11.0, çocuk/yaş etiketlerini bırakıp
  `ageRestrictedTreatment` (`CHILD`/`TEEN`) kullanır. Tasarım tek
  `age_restricted_treatment` anahtarına güncellendi; Legacy'ye dönüş gerekmedi.

### iOS

- GoogleMobileAds 13.11.0 ve UMP 3.1.0, Google'ın sürümlü SPM zip'lerinden
  (`tools/versions.env`) indirilir.
  - Zip SHA-256 değerleri `Package.swift` checksum'larıyla birebir eşleşti.
  - İkisi de statik xcframework; slice'lar `ios-arm64` ve
    `ios-arm64_x86_64-simulator`.
  - `MinimumOSVersion` 13.0; eklentinin hedefi iOS 15.
- Gizlilik manifestleri framework içinde gelir. Bootstrap bunları CocoaPods
  gibi `GoogleMobileAdsResources.bundle` ve `UserMessagingPlatformResources.bundle`
  içine sarar.
- `tools/bootstrap.sh` ilk çalıştırmada iki zip'i indirip doğruladı (38 MB açık);
  ikinci çalıştırma `.complete` ile 0,6 sn'de atladı.
- Self-hosted runner: son `Build addon` çalışması (5799ce2) Xcode 27.0 (27A266a)
  kullandı; GoogleMobileAds 13.11.0'ın en az Xcode 26.2 şartını karşılar.

## ADM-1…ADM-7 — uygulama kanıtı (2026-10-08, Linux)

- **ADM-1, API ve mock:** `tests/test_admob_mock.gd` ve
  `tests/test_admob_consent_mock.gd` modül yokken başarısızdı, şimdi geçiyor.
  Tam GDScript paketi (34 test) ve Python testleri geçiyor.
- **ADM-2, export:**
  - Android/iOS export testleri `--script` ve `--editor --script` modlarında geçiyor.
  - `tools/test_android_export.py` (Gradle 8.11.1, AGP 8.6.1, Kotlin 2.4.0,
    R8 9.1.29) altı sentetik seçimin debug ve R8 release APK'larını üretti.
    `auth,firestore,functions,admob` seçimi R8'de eksik sınıf vermedi.
  - APK manifestinde test App ID'li `com.google.android.gms.ads.APPLICATION_ID`
    var; AdMob seçilmeyen uygulamalarda yok.
- **ADM-3, ADM-4, native ve Android köprüsü:**
  - `javac --release 8` uyarısız.
  - NDK 28.2 ile `auth,firestore,functions,analytics,crashlytics,remote_config,admob`
    arm64 debug kütüphanesi `-Wl,--no-undefined` ile bağlandı. Dört
    `FirebaseAdmobBridge` JNI fonksiyonu dışa aktarılıyor; descriptor'lar
    `javap -s` ile eşleşti.
  - `tests/test_android_aar.sh` geçiyor.
- **APK boyutu (imzasız sentetik fixture, Godot motoru ve native `.so` hariç):**

  | Seçim | R8 release | Debug |
  |---|---|---|
  | `auth,firestore,functions` | 3,06 MB | 10,8 MB |
  | `auth,firestore,functions,admob` | 4,67 MB | 14,6 MB |

  AdMob'un R8 sonrası payı yaklaşık 1,5 MB.
- **ADM-5, iOS köprüsü:** yazıldı, Linux'ta derlenemez; macOS CI ile doğrulanacak.
- **ADM-6, paket:** paket testi AdMob tekil ZIP'ini ve dokuz modüllü seçimi kapsar.
  Masaüstü paket smoke'u `request_consent` mock çağrısıyla geçti.
- **ADM-7, SSV şablonu:**
  - `node --test` 31/31 geçti; ağ kullanılmadı.
  - Firestore Emulator kural testleri 6/6 geçti.
  - `examples/rewarded_energy.gd` gerçek Auth/Firestore/AdMob mock'larıyla
    yük→göster→ödül akışında enerjiyi 5 yaptı ve oyunu devam ettirdi
    (geçici test, commit edilmedi).

## Açık

- iOS derlemesi ve bağlama: ADM-5, macOS CI.
- Cihazda reklam, izin, iOS ATT ve SSV senaryoları; gerçek APK/IPA boyutu: ADM-8.
- Test reklamlarının SSV callback'lerinin hangi anahtar listesiyle imzalandığı: ADM-8.
