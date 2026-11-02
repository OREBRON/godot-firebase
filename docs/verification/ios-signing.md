# iOS SDK imzası ve Godot IPA kabulü

## Düzeltilen süreç

Önceki `tools/build.sh`, `xcodebuild -create-xcframework -library` ile çıplak
`.dylib` dilimleri oluşturuyordu. Paketleyici ve mobil workflow'lar Apple
imzası istemiyordu. Ayrıca Godot 4.7.2, bu dilimleri export sırasında framework'e
çevirirken binary'nin install name'ini ve plist'leri değiştiriyor; kaynak
XCFramework'ün imzasını taşımıyor. Yalnız bu eski XCFramework'e imza eklemek
export boyunca imza korunduğunu göstermez.

Yeni akış:

1. `tools/build_ios_xcframework.py` device/simulator dylib'lerini aynı adlı
   `.framework` dilimlerine kopyalar, `@rpath/<ad>.framework/<ad>` install name'ini
   ve oyun bilgisi içermeyen plist'leri hazırlar. `xcodebuild -create-xcframework
   -framework` tamamlandıktan sonra içerik imzalanabilir hâldedir. Orijinal build
   dylib'leri ve Crashlytics sembol girdileri değiştirilmez.
2. `tools/package.sh --sign-ios` ürün seçimini ve oyun konfigürasyon filtrelerini
   geçici paket dizinine uygular. Framework dilimlerini, ardından kapsayan
   debug/release XCFramework'lerini `codesign --force --timestamp --sign` ile
   imzalar. İmza sonrası içerik değiştirilmez.
3. `codesign --verify --strict --verbose=2` Apple güven zincirini ve beklenen
   Team ID'yi explicit requirement ile kontrol eder. `codesign -dvv` çıktısında
   Apple Distribution/Development kimliği ve güvenli timestamp aranır. Ad-hoc
   imza kabul edilmez.
4. Oluşan ZIP tekrar açılır; iki XCFramework ve içlerindeki dört framework
   aynı kontrollerden geçer. Ancak bundan sonra `build/dist/` çıktısı atomik
   olarak değiştirilir. Hatalı deneme önceki ZIP'i silmez/değiştirmez ve nonzero
   döner; `tools/release.sh` release yükleme adımına ilerlemez.

Godot 4.7.2'nin framework içeren XCFramework'ler için kullandığı yol doğrudan
kopyadır. Üretilen Xcode projesinde gömülen dinamik framework'ler
`CodeSignOnCopy` kullanır. SDK dağıtım imzası SDK ekibini tanıtır; uygulamaya
gömülen framework'ü Xcode oyun ekibinin sertifikasıyla yeniden imzalar.

Kaynaklar:

- [Apple: XCFramework oluşturma ve imzalama](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
- [Apple: Team ID ve Team Member ID ayrımı](https://developer.apple.com/forums/thread/811970)
- [Apple: geliştirme ve dağıtım sertifikaları](https://developer.apple.com/help/account/create-certificates/certificates-overview)
- [Godot 4.7.2 Apple export kodu](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/export/editor_export_platform_apple_embedded.cpp):
  `_convert_to_framework`, `_export_additional_asset`, `_add_assets_to_project`.

## Release Mac'i kurulumu

CI imzalamaz; imza yalnız release'i yayımlayan Mac'te `tools/release.sh` ile yapılır.
Geçerli Apple Distribution veya Apple Development sertifikası **özel anahtarıyla
birlikte** o kullanıcının Keychain'inde olmalıdır. Sertifikayı/özel anahtarı
depoya veya CI secret'larına koyma. `.p8`, App Store Connect API kimliğidir;
bu kod imzası için yeni `.p8` oluşturulmaz.

Ortam değişkenleri:

| Değişken | Değer |
| --- | --- |
| `IOS_SIGNING_IDENTITY` | Tam `Apple Distribution: …` / `Apple Development: …` sertifika adı veya 40 haneli sertifika SHA-1'i |
| `IOS_SIGNING_TEAM_ID` | SDK sahibinin 10 karakterli Apple Team ID'si |
| `IOS_SIGNING_KEYCHAIN` | İsteğe bağlı Keychain dosya yolu; boşsa varsayılan arama listesi |

`IOS_SIGNING_IDENTITY` ve `IOS_SIGNING_TEAM_ID` gerçek değerlerle doldurulmalıdır;
dummy değerler imzalama kontrolünü geçmez. Varsayılan Keychain kullanılıyorsa
`IOS_SIGNING_KEYCHAIN` gerekmez.

Development sertifika adındaki parantez bir üye ID'si olabilir; Team ID'yi bu
addan türetme. Beklenen Team ID, imzada sertifikanın `subject.OU` alanına karşı
doğrulanır. Kimlik adını/SHA-1'i Keychain Access'ten veya aşağıdaki komuttan al:

```bash
security find-identity -v -p codesigning
export IOS_SIGNING_IDENTITY='Apple Distribution: … (TEAMID)'
export IOS_SIGNING_TEAM_ID='TEAMID'
python3 tools/ios_signing.py check-identity
```

Preflight kimliğin geçerli sertifika/özel anahtar çifti olarak bulunduğunu
kontrol eder. Kilitli Keychain, özel anahtar ACL'i veya timestamp ağı sorunu
gerçek imzalama sırasında da hataya neden olabilir; hata bastırılmaz.

## SDK release kapısı

Eski dylib düzenindeki bir build'i yeniden paketlemek yerine yeni build üret:

```bash
tools/build.sh --platforms ios,android,macos \
  --modules auth,firestore,storage,database,functions,analytics,remote_config,crashlytics
tools/package.sh --sign-ios
python3 tools/ios_signing.py verify-package build/dist/godot-firebase.zip \
  --team-id "$IOS_SIGNING_TEAM_ID"
```

`tools/release.sh` bu imzalama kapısını zorunlu kullanır ve doğrulanmış ZIP,
semboller ve checksum'u tag'in release'ine yükler. `build.yml`, `packages.yml` ve
`sdk-capabilities.yml` imzasız paketler; bunlar yalnız derleme ve test kanıtıdır.

## Godot export ve son IPA kapısı

1. Oyundaki `addons/firebase` klasörünü doğrulanmış yeni SDK paketiyle güncelle.
   Önceki Xcode export'unu yeniden kullanma; Godot 4.7.2 ile temiz export üret.
2. Export edilen `dylibs/` ağacındaki
   `godot_firebase.ios.template_release.xcframework` kopyasının imzasını kontrol et:

   ```bash
   python3 tools/ios_signing.py verify-xcframework \
     /path/to/export/dylibs/.../godot_firebase.ios.template_release.xcframework \
     --team-id "$IOS_SIGNING_TEAM_ID"
   ```

   Xcode Build Phases → Embed Frameworks içinde Firebase framework için Code Sign
   on Copy açık olmalı. Godot'un ürettiği projenin bu ayarını kaldırma.
3. Xcode'da oyun ekibini, doğru bundle ID/provisioning profile ve dağıtım
   kimliğini seç; Archive ve IPA export'unu tamamla. Son IPA üzerinde çalıştır:

   ```bash
   python3 tools/ios_signing.py verify-ipa /path/to/SushiFusion.ipa \
     --team-id OYUNTEAMID --distribution
   ```

   Komut Firebase framework'ü olmayan IPA'yı reddeder. Bütün gömülü
   `.framework` imzalarını oyun ekibine karşı doğrular, sonra uygulamayı
   `--deep --strict` ile kontrol eder. SDK ekibiyle oyun ekibinin aynı olması
   gerekmez. `--distribution`, uygulama ve framework'lerde Apple Distribution
   sertifikasını zorunlu kılar; Apple Development ile imzalanmış IPA'yı yükleme
   öncesinde reddeder. Yerel cihaz geliştirme build'ini kontrol ederken bu bayrak
   kullanılmaz. IPA için XCFramework timestamp şartı uygulanmaz. Bu komut
   imzaları değiştirmez ve uygulamayı yüklemez.
4. Oyun CI'ında bu komutu IPA yüklemesinden önce zorunlu adım yap. Başarılı
   kontrolün ardından Xcode/App Store Connect doğrulaması ve yeni build yüklemesi
   yapılır. Provisioning/entitlement, cihaz çalışma testi ve App Store kabulü
   bu yerel imza kontrolünün ayrıca değerlendirilmesi gereken sonuçlarıdır.

## Kanıtın sınırı

- `python3 tests/test_ios_signing.py`: Linux'ta sentetik Apple araçlarıyla
  paketleme sırası, eksik/yanlış kimlik, ad-hoc/zaman damgasız/bozuk imza,
  ZIP'ten çıkarıldıktan sonra hata, eski çıktının korunması ve IPA takım
  uyuşmazlığı kontrol edilir. Bunlar gerçek Apple imzası kanıtı değildir.
- Aynı test dosyası macOS'ta `IOS_SIGNING_IDENTITY` varsa Xcode ile küçük gerçek
  device/simulator Mach-O dosyaları üretir, üretim framework/paketleme akışından
  geçirir ve binary değiştirildiğinde doğrulamanın reddettiğini sınar.
  `build.yml` bu testi kimlik preflight'ından sonra çalıştırır.
- Bu değişikliğin Linux oturumunda gerçek Keychain/codesign, Godot iOS export'u,
  son Sushi Fusion IPA'sı ve App Store yüklemesi çalıştırılmadı. Gerçek SDK ZIP'i,
  temiz Godot export'u ve son oyun IPA'sının macOS kanıtı release kabulünde
  kaydedilmelidir; test checkbox'ları bu kanıtların yerine geçmez.
