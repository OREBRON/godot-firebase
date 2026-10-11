# Agent yönergeleri

Bu depo Godot 4.7.2 için Firebase GDExtension eklentisidir: GDScript API (`addons/firebase/`) ve Firebase C++ SDK üzerine C++ modülleri (`src/`). Değişiklikleri mevcut modül, betik ve test düzenine uygun, anlaşılır ve yalnızca istenen kapsamda tut.

## Kod tasarımı

- **SOLID:** Sahne, sınıf ve fonksiyonların tek bir değişim nedeni olsun (SRP). Gerçek genişleme ihtiyacında davranışı mevcut kodu dağıtmadan genişlet (OCP). Alt türler üst türün beklenen davranışını korusun (LSP). Çağıranları kullanmadıkları geniş sözleşmelere bağımlı kılma (ISP). Yüksek seviyeli kuralları somut altyapı ayrıntılarına gereksiz yere bağlama (DIP). Bu ilkeler için sırf biçimsel uyum adına yeni katmanlar oluşturma.
- **DRY:** Aynı iş kuralı veya bilgiyi birden çok yerde tutma; ortak davranışı tek kaynağa taşı. Yalnızca görünüşte benzer, farklı nedenlerle değişen kodu zorla birleştirme.
- **KISS:** Doğrudan okunabilen en basit çözümü seç. Açık isimler ve kısa, odaklı fonksiyonlar kullan; gereksiz dolaylılık ve durum yönetiminden kaçın.
- **YAGNI:** Bugünkü gereksinim için gerekmeyen özellik, ayar veya soyutlamayı ekleme. Gereken yeniden düzenlemeyi ve testleri erteleme.

## Karmaşıklık ve yeniden kullanım

- **Tek sorumluluk:** Girdi, kurallar, sunum ve kalıcılık gibi farklı değişim nedenlerini uygun betik sınırlarında ayır. Bir fonksiyonun ne yaptığını adıyla açıklayabil.
- **Bilişsel karmaşıklık:** İç içe koşul ve döngüleri koruyucu koşullar, açık ara adımlar ve iyi adlandırılmış yardımcılarla sadeleştir; karmaşıklığı yalnızca başka fonksiyona taşıma.
- **Döngüsel karmaşıklık:** Bağımsız karar yollarını azalt; anlamlı dalları test et.
- **Yeniden kullanılabilirlik:** Bağımlılıkları açık tut; uygun yerde sinyal ve dışarıdan verilen yapılandırma kullan. Henüz tek kullanımlık kod için genel çatı kurma.
- Değişen davranışı ilgili testlerle doğrula; proje ve GDScript adlandırma/biçim düzenini izle.

## Modül sözleşmesi

- Sekiz ürün (`auth`, `firestore`, `storage`, `database`, `functions`, `analytics`, `remote_config`, `crashlytics`) üç parçadan oluşur: GDScript API (`<modül>/firebase_<modül>.gd`), mock (`<modül>/firebase_<modül>_mock.gd`) ve native sınıf (`src/<modül>/firebase_<modül>_native.*`). Native sınıf adı `capitalize()` sonucundaki boşluklar atılarak türetilir (`remote_config` → `FirebaseRemoteConfigNative`); özel eşleme eklenmez. Mock ile native sınıf aynı metot adlarını, argümanları ve sinyalleri kullanır; birini değiştirirken diğerini ve testleri de güncelle.
- Modüller birbirine bağımlı değildir; ortak kod yalnızca `addons/firebase/core/` ve `src/core/` içindedir (`firebase::Variant` dönüşümü: `src/core/variant_convert.*`; ortak Android JNI ve iOS sunum yardımcıları: `src/core/android_bridge.*`, `src/core/ios_presenter.*`). Mevcut üretim düzeninde yeni modül şuralara kaydedilir: `addons/firebase/core/firebase.gd` içindeki `MODULES` listesine adıyla ve aynı adlı bir özellikle (yollar ve native sınıf adı addan türetilir), `SConstruct` içindeki `MODULES`, `src/register_types.cpp`, `tools/bootstrap.sh` içindeki kütüphane ve Firebase.zip klasör listeleri, `tools/build_android_aar.sh` içindeki ProGuard modül listesi ve `addons/firebase/export/firebase_android_gradle.gd` içindeki Maven `DEPENDENCIES` eşlemesi. Platform köprüsü kullanan modüller köprü derleme bağımlılığını `android/build.gradle` (lock ve verification metadata ile), iOS ikili pinlerini `tools/versions.env` içinde tutar.
- Native kod geçersiz girdide çökmemelidir: Firebase C++ SDK birçok hatalı argümanda süreci sonlandırır. Kullanıcıya okunur hata GDScript katmanında verilir, native katman aynı kuralları savunma amaçlı tekrarlar.
- Firebase yanıtları başka thread'lerde gelir; sinyaller yalnızca `FirebaseModuleNative` üzerinden ana thread'e taşınarak yayılır.
- Crashlytics pinned C++ SDK'da normal `firebase_crashlytics` arşivi değildir; Android Java/NDK ve iOS Objective-C++ köprülerini kullanır. Platform bağımlılıkları oyun export'unda seçilir. Analytics/Auth zorunlu Crashlytics bağımlılığı değildir; UID/consent modüller arasında otomatik eşlenmez. Log/nonfatal/send/delete task'ı upload ACK'i değildir.

## Paket ve build sahipliği

- Mevcut `tools/build.sh` seçili ürünleri tek native kütüphaneye bağlar; `tools/package.sh` `addons/firebase/bin/modules.txt` üzerinden o seçimin ZIP'ini üretir. Tek modül ZIP'lerini üst üste açmak native dosyaları değiştirir; bugün composable olduklarını iddia etme. API klasörü silmek mevcut native/Maven seçimini azaltmaz. Platform çıktılarının aynı seçimden geldiğini build sahibi sağlamalıdır; mevcut paketleyicide stale-build reddi yoktur.
- Hedef altı paket ve kurulum/migration sözleşmesi `README.md` içinde; tasarım ve sıralama `docs/superpowers/specs/2026-09-30-modular-packages-design.md` ve `docs/superpowers/plans/2026-09-30-modular-packages.md` içinde. `docs/verification/modular-release.md` mevcut uygulama, prototip ve bekleyen kabulü ayırır. Plan checkbox'larını runtime kanıtı olarak kullanma.
- #224 sekiz ürün API'sini development build/ZIP/CI seçimine ekler; üç yeni tekil + sekiz ürün full ile dokuz ZIP hedefi takip release'idir. Eski altı-paket kabulünü genişleterek tamamlanmış sayma. Sekiz ürünlü monolit geliştirme ZIP'i `godot-firebase-sdk-capabilities.zip`, remote_config tekili `godot-firebase-remote-config.zip`; eski beş ürün full `godot-firebase.zip` kalır. Yeni workflow yalnız artifact üretir, release yayımlamaz. Güncel kanıt `docs/verification/sdk-capabilities.md` içindedir.
- #90 platform kararı cihaz kanıtına kadar ertelendi. #85/#86/#87/#88/#54 üretim düzenini, #67 paketleri, #68 CI'ı sahiplenir. Seçilmemiş native topolojiyi üretim sözleşmesi olarak yazma; universal platformda kullanılmayan native ürünlerin yokluğunu vaat etme.
- Hedef düzende Core/ortak platform çıktıları release başına bir kez stage edilir; ürün build'i bu yolları değiştirmez. Ürüne özgü API/mock, native descriptor/binary ve metadata ürün klasörüne aittir. Full ZIP beş tek modül ZIP'inin birleşimidir; ayrı Core ZIP yoktur. Ortak yollar bayt olarak aynı, ürün yolları ayrık olmalıdır. Bu kurallar #67 tamamlanana kadar hedef sözleşmedir.
- #85 sonrasında Core/ürün `package.json` dosyalarında tek immutable `build_id` kullanılır; aynı ID native'e gömülür. SDK/toolchain bilgisi provenance içindir, ayrı uyumluluk anahtarı değildir. Manifest discovery mevcut `modules.txt` doğruluk kaynağını değiştirir; ikisini paralel sürdürme. Geçiş tamamlanmadan manifest kontrolünün var olduğunu varsayma.
- Hedef ortak App/dispatch Core'a aittir; callback davranışını modüllerde çoğaltma. Seçilen split backend'de bütün modül yüklemeleri ve SDK kayıtları App yaratımından önce tamamlanır; App öncesi build ID kontrolü gerekir. Runtime hot unload desteklenmez.
- Paket kabulü (#67) ortak path+SHA256 eşitliği, ürün yolu ayrıklığı, full=union, stale/mixed build reddi ve oyun config'inin dışlanmasını kapsar. Beş tekil/full/Auth+Firestore/Auth+Database smoke ve ters/tekrar import, Core-only, kaldırma testleri ayrıca gerekir. Statik birleşim kanıtı #55/#59 oturum, token, callback ve shutdown cihaz testlerinin yerine geçmez.

## Depoda çalışma

- Testler: `GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/run_tests.sh`. Her test `FirebaseTest` tabanını kullanır; takılan veya script hatası veren test başarısız sayılır.
- Firebase C++/iOS ve godot-cpp `tools/versions.env`, GoogleSignIn kaynakları `tools/google_signin_ios/Podfile` ve lock dosyası, Android bridge `android/build.gradle` ve lock dosyası, oyun Maven/Kotlin/R8 seçimleri `addons/firebase/export/firebase_android_gradle.gd` içinde sabitlenir; indirilen ve derlenen dosyalar depoya girmez.
- Oyuna ait `GoogleService-Info.plist` ve `google-services*.json` dosyaları eklentiye eklenmez. Android'de JSON export sırasında pakete eklenir ve çalışma zamanında `FirebaseAndroidConfig` ile okunur; native ve AAR build'leri oyun bilgisi almaz.
- Android export helper'ı seçili Firebase modülleri için standart Godot `config.gradle` / `settings.gradle` içinde geri alınabilir Kotlin 2.4.0 / R8 9.1.29 bloklarını yönetir; AGP'yi değiştirmez. Özel template veya değiştirilmiş yönetilen bloklarda hata verir. Analytics/Crashlytics seçiliyse oyun JSON'undan başlangıç kaynakları üretir; bunlar generic AAR'a girmez. `tools/test_android_export.py` beş sentetik uygulamada aynı AAR ile debug/R8 APK üretimini doğrular; Godot engine/native `.so` veya cihaz runtime kabulü değildir.
- Crashlytics seçili build sembolleri `build/symbols/<selection>/` altında tutar; Android GNU build ID ve iOS UUID/DWARF eşleşmesi `tools/verify_crashlytics_symbols.py` ile doğrulanır. Oyun R8 mapping'i ve Godot engine sembolleri ayrı export girdileridir. `tools/upload_crashlytics_symbols.sh` yalnız açıkça çağrıldığında yükler; build/CI implicit upload yapmaz. Cihaz crash/restart ve console symbolication yerel mock/build testinden çıkarılamaz.
