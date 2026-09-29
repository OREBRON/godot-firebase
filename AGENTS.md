# Agent yönergeleri

Bu depo Godot 4.7.2 için Firebase GDExtension eklentisidir: GDScript API (`addons/godot_firebase/`) ve Firebase C++ SDK üzerine C++ modülleri (`src/`). Değişiklikleri mevcut modül, betik ve test düzenine uygun, anlaşılır ve yalnızca istenen kapsamda tut.

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

- Her modül (`auth`, `firestore`, `storage`, `database`, `functions`) üç parçadan oluşur: GDScript API (`<modül>/firebase_<modül>.gd`), mock (`<modül>/firebase_<modül>_mock.gd`) ve native sınıf `Firebase<Modül>Native` (`src/<modül>/firebase_<modül>_native.*`). Mock ile native sınıf aynı metot adlarını, argümanları ve sinyalleri kullanır; birini değiştirirken diğerini ve testleri de güncelle.
- Modüller birbirine bağımlı değildir; ortak kod yalnızca `core/` ve `src/core/` içindedir (`firebase::Variant` dönüşümü: `src/core/variant_convert.*`). Yeni modül şuralara kaydedilir: `core/firebase.gd` içindeki `MODULES` listesine adıyla ve aynı adlı bir özellikle (yollar ve native sınıf adı addan türetilir), `SConstruct` içindeki `MODULES`, `src/register_types.cpp` ve `tools/bootstrap.sh` içindeki kütüphane ve Firebase.zip klasör listeleri.
- Native kod geçersiz girdide çökmemelidir: Firebase C++ SDK birçok hatalı argümanda süreci sonlandırır. Kullanıcıya okunur hata GDScript katmanında verilir, native katman aynı kuralları savunma amaçlı tekrarlar.
- Firebase yanıtları başka thread'lerde gelir; sinyaller yalnızca `FirebaseModuleNative` üzerinden ana thread'e taşınarak yayılır.

## Depoda çalışma

- Testler: `GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/run_tests.sh`. Her test `FirebaseTest` tabanını kullanır; takılan veya script hatası veren test başarısız sayılır.
- Native bağımlılıklar `tools/versions.env` içinde sabitlenir; indirilen ve derlenen dosyalar depoya girmez.
- Oyuna ait `GoogleService-Info.plist` ve `google-services*.json` dosyaları eklentiye eklenmez.
