# Modüler release doğrulama durumu (#91 / #68)

Tarih: 2026-09-30. #91 belge çalışmasının kaynak tabanı:
`1cc81b55246f8085bb0769420d1cf5d54a0dc3f0`. Bu dosya yayın kabulünü
kaydeder; altı birleşebilir ZIP veya cihaz testi bu belge çalışmasında üretilmedi.

## Kaynaklar ve durum ayrımı

- Kullanıcı kurulumu ve temiz migration: [README](../../README.md).
- Build/modül sahipliği: [AGENTS](../../AGENTS.md).
- Hedef sözleşme: [tasarım](../superpowers/specs/2026-09-30-modular-packages-design.md).
- İş sırası ve kartlar: [plan](../superpowers/plans/2026-09-30-modular-packages.md).
- Gerçek fixture boyutları: [#56 boyut raporu](modular-size.md).
- ELF/link, Core/ObjC sahipliği ve host/export prototipleri:
  [#83/#84 native raporu](modular-native.md).

Plan/spec'in ilk “mevcut durum” paragrafları ve iş checklist'leri planlama
anındaki tespitlerdir. Sonraki platform durumu, board bulguları ve kaynak
kodla birlikte okunmalıdır: #56 ölçümleri yapıldı, Android runtime config
üretim koduna alındı; cihaz kabulü hâlâ açıktır. “Henüz ölçüm yapılmadı” ve
“AAR oyun XML'i taşır” ifadeleri bugünkü uygulamanın durumu değildir.
Spec #89 kodunun tamamlandığını anlatır; board #89 `doing`, çünkü cihaz
ve default-App yükleme sırası kabul maddeleri açık. #91 kapsamındaki kaynak
kontrolünde graph generation `2026-09-30T11:40:28Z` kullanıldı; mevcut aday
GDScript yollarında kaydedilmiş coverage boşluğu bulunmadı (tamlık garantisi değil).

## Bugün çalışan üretim düzeni

| Alan | Kaynakta görülen davranış | Kanıtın sınırı |
| --- | --- | --- |
| Native build | `SConstruct` / `tools/build.sh`, seçili ürünler için tek `libgodot_firebase` | Ayrı ürün native üretim düzeni yok |
| Paket | `tools/package.sh`, `bin/modules.txt` ile seçili API klasörlerini tutar | Aynı native yollar; tekil ZIP'ler birlikte kurulamaz; stale platform kontrolü yok |
| API keşfi | `core/firebase.gd` `_create_backends`, API dosyası varlığı | Manifest veya `build_id` kontrolü yok |
| Autoload | `plugin.gd` `_enable_plugin`, tek `Firebase` singleton | Modül başına autoload yok |
| Android bağımlılıkları | Export eklentisi ürün Maven listesini `bin/modules.txt` ile seçer; ortak Analytics/Play Services eklenir | API klasörü silmek Maven listesini değiştirmez |
| Android oyun config'i | Export'ta JSON oyuna eklenir; `FirebaseAndroidConfig` gerçek package client'ını seçer; bridge explicit `AppOptions` kullanır (#89) | Generic AAR/native build oyun bilgisi almaz; device/Java default App/restart/minification açık |
| Hatalı Android config | Export penceresi uyarısı; runtime Firebase başlatılmaz | Godot 4.7.2 export eklentisi export'u durduramaz |

## Platform kararı ve ölçümler

**#90 kararı bekliyor:** Kullanıcı cihaz kanıtından önce native backend
seçmedi. Android A (universal) önerisi ve iOS B (ayrı `.gdextension`)
prototipi kesinleşmiş üretim topolojisi değildir.

| Kanıt | Doğrulanan sonuç | Açık kalan |
| --- | --- | --- |
| #56 Android a2 − a1 | Native fark 1,405,384 B; APK +%1.63, Maven sabit | Full native + Auth Maven cihaz cold-start ve `App::Create` |
| #56 Android a3 − a2 | Maven farkı 7,989,069 B; APK +%9.10, full native sabit | Seçili bağımlılıklarla runtime uyumu |
| #56 iOS full − Auth | Native +15,800,592 B; unpacked app +15,840,069 B (+%17.4); imzasız IPA zip +5,708,044 B (+%22.3) | İmzalı IPA ve App Store thinning |
| #83 B prototipi | Android ELF/link, Core export, shared STL; macOS Godot host yükleme/kayıt testi | Android cihaz yükleme, RTTI/allocator sınırı, oturum ve shutdown |
| #84 B prototipi | iOS Core/Auth/Firestore link, ObjC tek sahiplik, Godot export + imzasız Xcode build; Auth-only native tasarruf 14,798,240 B (universal full'a göre) | Simulator/cihaz cold-start, duplicate class logu, Auth → UID-korumalı Firestore, signing |

Android `.so` farkı APK'nın Maven farkıyla toplanmadan ayrı gösterilir.
iOS imzasız `zip -9` çıktısı App Store indirme boyutu değildir. Universal
platform seçilirse kullanılmayan native ürünler ortak binary'de kalabilir;
API seçimi native ürün dışlaması olarak sunulmaz. Platformlara farklı
backend seçilmesi aynı altı ZIP kullanıcı deneyimini koruyabilir.

## Hedef release kabulü

Bu checklist gerçek çıktılar geldikçe #67/#68 sahipleri tarafından kanıt
yolu, kaynak commit'i ve çalıştırılan komutla güncellenir. Dosya/test isimleri
planlanan adlardır; henüz varlıkları veya geçtikleri iddia edilmez.

| Kabul | Kart / beklenen kanıt | Durum |
| --- | --- | --- |
| Platform başına backend ve üretim arayüzü | #90, erken #55/#59 cihaz kanıtı | Bekliyor |
| Tek release `build_id`, native/App öncesi mismatch reddi | #85/#86 | Bekliyor |
| Core + beş ürün stage'i; seçilen backend | #87/#88; `tests/test_native_layout.py` | Bekliyor |
| iOS descriptor/framework/resource sahipliği | #54; `tests/test_ios_package_layout.py`, export/signing | Bekliyor |
| Altı exact ZIP adı, ayrı Core gerekmemesi | #67; `tests/test_packages.py` | Bekliyor |
| Ortak path/bayt eşitliği, ürün yolu ayrıklığı, full=union | #67; aynı testte path+SHA256 kanıtı | Bekliyor |
| Eksik/eski platform build reddi, oyun config'i dışlama | #67; paket içerik ve hata testleri | Bekliyor |
| Beş tekil + full + Auth/Firestore + Auth/Database smoke | #67; `tests/test_package_import.sh` | Bekliyor |
| Ters/tekrar import, tekilden full'a, Core-only, kaldırma | #67; import fixture'ları | Bekliyor |
| Tek release build'inden CI, Android preflight/cache, SHA256SUMS | #68; workflow çalışması | Bekliyor |
| iPhone beş ürün, Apple/Game Center/link/delete, oturum/token/main-thread/shutdown | #55 | Cihaz kanıtı yok |
| Android default App, iki oyun aynı prebuilt, beş ürün/token/restart/minification/shutdown | #59 ve #89 | Fixture Gradle export var; cihaz kanıtı yok |

Statik dosya birleşimi tüm 31 modül seçiminin dosya kümesini kapsayabilir;
31 runtime döngüsü yapılması planlanmaz. Yukarıdaki smoke testleri native
cihaz E2E yerine geçmez. CI build/test'i cihaz beklemeden geliştirilebilir,
ancak native release kabulü eksik cihaz kanıtını geçmiş sayamaz.

Hedef ZIP'ler: `godot-firebase.zip`, `godot-firebase-auth.zip`,
`godot-firebase-firestore.zip`, `godot-firebase-storage.zip`,
`godot-firebase-database.zip`, `godot-firebase-functions.zip`.
Mevcut CI aynı adlı varyantlar üretebilir; ad benzerliği bu kabulün geçtiğini
göstermez.

## #91 belge teslimi ve handoff

README'de mevcut kombinasyon build'leri, hedef dört import seçimi, ortak
Core/tek autoload, tekrar/ters import, modül kaldırma, bütün seçili modülleri
aynı build'den yükseltme ve eski monolitten temiz geçiş yazıldı. AGENTS mevcut
kayıt noktalarını korur ve hedef Core/ürün/stage sahipliğini ayrı anlatır.

#91'in nihai kabulü #90 ve #67 sonucu olmadan kapatılamaz. Bu kart için:

1. #90 kesinleşince README platform paragrafını ve bu rapordaki kararı güncelle.
2. #67 sonrasında gerçek ZIP'lerle kurulum/migration örneklerini doğrula;
   hedef etiketi ancak kanıt varsa kaldır. Ürün yolları değişirse kaldırma
   talimatlarını gerçek paket envanterine göre düzelt.
3. #68 CI ve #55/#59 cihaz kanıtlarının kaynak/komut/çıktılarını ekle;
   doğrulanmamış satırları bu kanıt gelene kadar açık tut.

Bu belge çalışmasının kontrolleri: sekiz Godot mock/config test dosyası
temiz worktree'de geçti; JSON ve listener negatif senaryolarının beklenen
`ERROR` logları görüldü. Markdown bağlantı/anchor ve diff kontrollerinin
sonucu #91 kartında kayıtlıdır. Yeni ZIP, native build veya cihaz testi
çalıştırıldığı iddia edilmez.
