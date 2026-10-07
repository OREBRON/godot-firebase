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

## Açık

- R8'li release APK boyutu ve AdMob kuralları: ADM-4/ADM-8.
- iOS derlemesi ve bağlama: ADM-5, macOS CI.
- Cihazda reklam, izin ve SSV senaryoları: ADM-8.
