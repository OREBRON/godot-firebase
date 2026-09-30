# Godot Firebase Modular Packages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Alt ajanlar ancak kullanıcı ayrıca seçerse kullanılır.

**Goal:** Bir tam Firebase ZIP'i ve birbirine eklenebilen beş tek modül ZIP'i; oyun başına native yeniden derleme olmadan kurulum.

**Architecture:** Paket formatı sabittir; native backend platform başına ölçüm ve prototiple seçilir. Ayrı `.gdextension`, tek Core/custom loader ve ortak universal binary karşılaştırılır. Android oyun konfigürasyonu native karar kapısından bağımsız çözülür.

**Tech Stack:** Godot 4.7.2 / GDScript, C++ / godot-cpp / Firebase SDK, SCons, Bash/Python, Android Java/AAR/Gradle, iOS XCFramework.

**Spec:** [2026-09-30-modular-packages-design.md](../specs/2026-09-30-modular-packages-design.md)

## Global Constraints

- Godot 4.7.2, Godot API 4.7.
- Firebase C++ SDK 13.13.0, Firebase iOS SDK 12.19.1; `tools/versions.env` tek sürüm kaynağıdır.
- iOS minimum 15.0; device arm64 ve simulator arm64.
- Android arm64-v8a; SDK platform 35 ve mevcut NDK düzeni.
- macOS arm64 editör stub'ı ve masaüstü mock davranışı korunur. Masaüstü Firebase, Web, yeni Firebase ürünleri kapsam dışıdır.
- Altı ZIP; kombinasyon release'leri veya kullanıcıda eklenti native build'i yok.
- Aynı immutable `build_id` tüm parçalara gömülür. Ayrı schema/native_abi/SDK uyumluluk alanları eklenmez.
- Mevcut API/mock/native sözleşmesi, input savunması ve ana thread teslimi korunur.
- Oyuna ait JSON/plist veya üretilmiş oyun ayarları release paketlerine girmez.
- Ölçüm veya native topoloji henüz doğrulanmış değildir. Bu görevler planlandı; uygulama başlamadı.

## Review Focus

- Full native + seçili Maven: yükleme ve statik callback'ler eksik Java ürününe ihtiyaç duyarsa küçük dependency closure varsayımı reddedilir (Task 0, 1a).
- C++ runtime ve symbol interposition: DSO'lar arası allocator/registry/binding sahibinin yanlış kopyasına bağlanılmaz (Task 1a, 1b).
- Initialization sırası: bütün kurulu ürünler default Firebase App oluşturulmadan önce yüklenir; Android provider dahil (Task A, 1a, 3a).
- Mixed build, eksik/bozuk binary ve modül kaldırma: okunur hata veya kurulu değil sonucu birbirinden ayrılır (Task 2, 3a, 5).
- Import dosya birleşimi native davranış kanıtı değildir; token, callback ve shutdown cihazda ayrıca doğrulanır (Task 1c, 5).

## Agentboard eşlemesi ve sıra

| Görev | Kart | Önkoşul |
| --- | --- | --- |
| 0: Native ve uygulama boyutlarını ölç | #56 | Başlangıç; mevcut görev genişletildi |
| A: Android config'i prebuilt'ten ayır | #89 | Başlangıç; native split gate'inden bağımsız |
| 1a: Android ELF/load adayları | #83 | Ölçümden split adayına gerekçe; config zamanlaması için A bulguları |
| 1b: iOS link/ObjC sahipliği | #84 | Aynı aday 1a'dan geçti; platform bağımsız gerekçe varsa raporlanan istisna |
| 1c: Erken Auth+Firestore cihaz kanıtı | #55, #59 | Prototype link/export; kartların nihai acceptance tamamlanması beklenmez |
| D: Platform kararını kaydet | #90 | 0, A, ilgili 1a/1b ve erken 1c kanıtları; final #54/#55/#59 sonucuna bağımlı değil |
| 2: Build kimliği ve discovery | #85 | D; native tercih sabitlendi |
| 3a: Core ve yaşam döngüsü | #86 | D, 2; yalnız seçilen backend uygulanır |
| 3b: Auth + Firestore üretim düzeni | #87 | 3a |
| 3c: Storage/Database/Functions | #88 | 3b |
| 4: iOS export sahipliği | #54 | D, seçilen backend'in 3a/3b çıktıları |
| 5: Altı ZIP ve import doğrulaması | #67 | 2, üretim bileşenleri, A, 4 |
| 6: CI ve release doğrulaması | #68 | Build/paket düzeni; cihaz kanıtı release kabulüne bağlı |
| 7: Kurulum/migration belgeleri | #91 | D ve 5; nihai runtime kanıtı #55/#59 |

#54/#55/#56/#59/#67/#68 mevcut kartlar yeniden kullanıldı; aynı iş için ikinci kart açılmadı. #67'nin eski platform `modules.txt` yaklaşımı yeni component/build_id sahipliğiyle, #68'in eski varyant döngüsü yeni release düzeniyle yer değiştirir; geçmiş kapsam kartlarda korunur.

## Task 0: Boyut ve bağımlılık farkını ölç — #56

**Files:** Geçici `build/probes/package-size/`; rapor `docs/verification/modular-size.md`. Üretim kaynaklarını değiştirmeden mevcut SCons modül seçimini kullan.
**Output:** Platform/variant başına stripped native, APK/IPA compressed, uygulama unpacked, Maven/iOS dependency closure, mutlak/yüzde fark ve exact link/export ayarları.

- [ ] Aynı minimal fixture, Godot export template, oyun config'i, asset seti, minification ve mimariyle `auth` ile `auth,firestore,storage,database,functions` release build'lerini al. Signed IPA mümkün değilse native/unpacked sonucu ver; IPA ölçümü yapılmış gibi yazma.
- [ ] Geçici çıkış kökleri kullan; varyant build'inin diğerine ait binary/resource/config'i taşımasını önle. Kullanıcının diğer oyun deposunu değiştirme; önceki Moonlight boyut takibi gerekli olduğunda ayrı yetkili takip işi olarak korunur.
- [ ] iOS link komutunda `-dead_strip`, Android strip/section-GC sonucunu kaydet. Default bayrakları varsayma; prototipte gerekli flag farklarını rapora yaz.
- [ ] Üç Android fixture karşılaştır: Auth native+Auth Maven, full native+Auth Maven, full native+full Maven. İkinci fixture yükleme/initialize edemezse farkı geçerli küçük-universal örneği olarak sunma.
- [ ] `rtk otool -L <ios-binary>`, `rtk <ndk>/llvm-readelf -d <android-so>` ve artifact içerik/boyut dökümüyle hangi byte'ların native/Java/framework kaynaklı olduğunu raporla. Araç placeholder'ı yerine kullanılan gerçek NDK yolunu kanıt raporuna yaz.
- [ ] Android ve iOS için bakım maliyetiyle birlikte topoloji öner; kullanıcı tarafından belirlenmemiş bir MiB/yüzde eşiğini otomatik kabul kuralı yapma.

## Task A: Android config'i native gate'den bağımsız çöz — #89

**Files:** `src/core/firebase_app_native.*`, `FirebaseBridge.java`, `tools/build_android_aar.sh`, `tools/build.sh`, `firebase_android_export_plugin.gd`, `tests/test_android_aar.sh`; fallback gerekirse `firebase_android_config.gd`, `tests/test_android_config.gd`.
**Output:** Bir generic bridge AAR; tek seçilmiş konfigürasyon yolu. Export seçeneği `firebase/google_services_json`, varsayılan `res://google-services.json`.

- [ ] Failing test: genel AAR JSON olmadan üretilir, `googleservices.xml` içermez; iki farklı oyun aynı bridge/native hash'ini kullanır. `rtk bash tests/test_android_aar.sh` ile mevcut hatayı gör.
- [ ] Runtime AppOptions prototipinde JSON client'ını gerçek Android package kimliğiyle seç. `AppOptions::LoadFromJsonConfig` ve `App::Create(options, env, activity)` sonucunu incele; first-client seçimine güvenme.
- [ ] `FirebaseInitProvider` ve Java default App'ın erken oluşturulması, resource okuyan ürünler, `default_web_client_id` ve mevcut auth sağlayıcılarını kontrol et. Yanlış package, çok client, eksik app ID/API key, restart ve aynı native/Java default App testlerini kaydet.
- [ ] Runtime config bütün mevcut ürünlerde çalışırsa yalnız o yolu uygula. Çalışmazsa pinned converter XML values/escaping/keep sonucunu eşleyen GDScript converter + export-time resource AAR uygula. İki fallback production hattı birlikte kalmasın.
- [ ] Native build'den JSON/package zorunluluğunu kaldır. Hatalı config export preflight'ını başarısız kılsın; debug/release bridge doğru binary'yi yüklesin.
- [ ] AAR testi, Godot suite ve #59 Android device/minification kontrolüyle sonucu doğrula; config kaynak kodu ayrı commit olsun. Bu görev 1a/1b başarısız olsa da tamamlanabilir.

## Task 1a: Android ELF/load; iki split aday — #83

**Files:** Yalnız `build/probes/modular-native/android/`; rapor `docs/verification/modular-native.md`.
**Output:** Her aday için pass/fail, exact export list, link/runtime/loader kararı. Geçici prototip üretim değildir.

- [ ] Önce ayrı `.gdextension` adayı B'yi Core/Auth/Firestore ile dene. Modüller kendi isolated godot-cpp binding'ini kullanır; Core base class mirası yerine ortak hizmet/composition sınırını sınar. Class/instance-binding kimliği ve callback nesne sahipliğini kontrol et.
- [ ] B başarısızsa veya daha pahalıysa tek Core/custom loader adayı C'yi dene. Core yalnız beş sabit library adını probe etsin; C++ JSON/res:// discovery ekleme. Eksik opsiyonel library ile mevcut ama yüklenemeyen library farklı sonuç versin.
- [ ] Gerçek link komutları ve `llvm-readelf -d` ile uyumlu tek `libc++_shared.so` kullanımını doğrula; APK'da tek kopya, Godot ve AAR/middleware uyumu kontrol edilsin. DSO sınırında allocate/free ve gerekiyorsa exception/RTTI davranışını test et. Clang default'u gerçek binary kanıtı yerine kullanma.
- [ ] `llvm-nm --undefined-only`/`--defined-only`, link map ve ELF version script ile imports/exports çıkar. Core App/registry'nin tek sahibi olsun; B'de godot-cpp gizli, C'de tek binding runtime bilinçli export edilmiş olsun.
- [ ] Archive-scoped `--whole-archive ... --no-whole-archive` ihtiyacını dar force-reference/export ile karşılaştır; Firebase internal/util import closure'ı ve initializer retention kanıtı kaydet. Whole-archive visibility sorununu tek başına çözmez.
- [ ] Fixture `events` iziyle tüm module load/SDK registrars olaylarının C++/Java default App creation'dan önce olduğunu doğrula. `FirebaseInitProvider` nedeniyle invariant sağlanamıyorsa aday fail sayılır.
- [ ] APK cold-start/link/load ve missing/mismatched binary testini yap; Auth token E2E ve uzun shutdown testi 1c'ye aittir. Aynı aday fail ise 1b'ye taşınmaz.

## Task 1b: iOS link/ObjC/Swift sahipliği — #84

**Files:** Yalnız `build/probes/modular-native/ios/`; aynı native kanıt raporu.

- [ ] 1a'dan geçen adayla Core/Auth/Firestore device/simulator link al. Android split'ten bağımsız iOS gerekçesi varsa bunu #90'da kaydetmeden yeni platform dalı açma.
- [ ] Ortak aday envanterini çıkar: `FirebaseCoreExtension`, `FirebaseAppCheckInterop`, `FirebaseSharedSwift`, `FirebaseAuthInterop`, mevcut Core listesi ve modül closure'ının diğer ortak framework'leri. Her ObjC/Swift implementasyonu tek binary sahibi olsun.
- [ ] `rtk otool -L <binary>` ve `rtk nm -g <binary>` ile `@rpath`, install name, exported-symbols list ve duplicate class/symbol sahipliğini denetle. Dar `-force_load` gereksinimini ve strip sonrası registrars'ı kaydet.
- [ ] Simulator cold-start'ta duplicate ObjC class uyarısı olmamalı. B için Godot descriptor export, C için özel embedding/signing yolunu #54 ile doğrula.
- [ ] Link/load sonucu ve doğrulanamayan gerçek cihaz adımlarını ayrı raporla. Bu görev token yenileme/E2E projesine genişletilmez.

## Task 1c: Erken cihaz kanıtı ve sonraki final regression — #55, #59

İki mevcut cihaz kartı aşamalı kullanılır: #90 için yalnız prototip Auth+Firestore kanıtı gerekir; kartın bütün ürün acceptance'ının tamamlanması gerekmez. Production #54 export ve Database/Storage/Functions final regression, 3c/4 sonrasında yapılır. Böylece #90 → production → #90 döngüsü oluşmaz.

- [ ] Erken Android/iOS prototipinde anonim Auth → UID-korumalı Firestore write/read → sign-out → reddedilen erişim akışını çalıştır. Geçici prototype export'u kullan; production #54 tamamlanmasını bekleme.
- [ ] Yeniden giriş/token yenilenmesi sonrası yeni oturumun diğer ürünlerce görülmesini doğrula; yalnız aynı App adresi kontrolü yeterli değil.
- [ ] Async sinyal ana thread'e gelsin; listener/nesne serbest bırakma ve shutdown sırasında use-after-free/çökme oluşmasın.
- [ ] 3c/4 sonrasında final regression'da UID-korumalı Database, full Storage/Functions ve mevcut #55 sign-in/link/delete acceptance'ını tamamla. #59 release/minification final testi de geçsin. Auth olmadığı seçimler için ürüne uygun izin fixture'ı kullan.
- [ ] Eksik cihaz/config erişimini kartta kaydet; link veya mock sonuçlarıyla maddeleri tamamlanmış işaretleme.

## Task D: Platform kararı ve fallback'i sabitle — #90

**Files:** Spec/plan ve `docs/verification/modular-native.md`, `modular-size.md`.
**Output:** Android/iOS için birer `universal`, `separate-gdextension` veya `core-loader` kararı; gerekçe, beklenen kurulum/çıktı boyutu ve üretim görev sınırları.

- [ ] 0/A/1a/1b ve erken 1c sonuçlarını birleştir; size sonucu olmadan split gerekli veya universal yeterli deme.
- [ ] B başarısızsa C; C başarısızsa universal. Android universal+iOS split veya tersi aynı altı ZIP formatıyla mümkün. Universal için seçili Maven ile initialize kanıtı yoksa dependency bedelini açıkça yaz.
- [ ] Hiçbir aday çalışmıyor veya universal boyut bedeli kabul edilmiyorsa native production 2/3/4 görevleri gate'de açık kalır. A ve statik ZIP test tasarımı bağımsız ilerleyebilir; bozuk release yayımlanmaz.
- [ ] Platform tercihini üretim düzenine geçmeden kullanıcı incelemesine sun. Sonra aşağıdaki koşullu görevlerde yalnız seçilen backend'in dosya/imza/test kararlarını kesinleştir; üç backend'i birlikte implement etme.

## Task 2: Tek build_id ve paket discovery — #85

**Files:** `tools/firebase_modules.json`, `tools/firebase_packages.py`, `addons/firebase/core/firebase_packages.gd`, `tests/test_package_manifests.py`, `tests/test_firebase_packages.gd`.
**Interfaces:** `FirebasePackages.discover(root_path: String) -> Dictionary` sonucu `{ok, core, modules, errors}`; metadata `build_id`, `module`; Python `stage_components(build_root: Path, stage_root: Path, build_id: str) -> None`.

- [ ] Test `test_mixed_build_rejected`: aynı ID kabul, farklı ID reddedilir. `test_module_paths_disjoint`: paket kökü dışı path ve bilinmeyen modül reddedilir; Core-only boş kümedir.
- [ ] `rtk python3 -m unittest discover -s tests -p 'test_package_manifests.py'` ve Godot suite ile failing sonucu gör; minimum metadata/discovery'yi uygula ve yeniden geçmesini doğrula.
- [ ] ID'yi kaynak commit + pinned dependency hashes + ortak toolchain/build recipe'den bir kez üret; bütün binary/manifest'e aynı değeri göm. Release tag'i provenance içindir; ayrı schema/ABI/SDK eşitlik sistemi kurma.
- [ ] GDScript/export manifest okur; native sabit entry ve ID okur. Oyunun config değerleri metadata/log'a girmez. Bu görevi ayrı commit et.

## Task 3a: Core sahipliği ve init/shutdown — #86

**Files:** `src/register_types.cpp`, `src/core/firebase_app_native.*`, `src/core/firebase_module_native.*`, `addons/firebase/core/firebase.gd`, seçilen backend için Core descriptor/entry kaynakları.

- [ ] Test `test_modules_loaded_before_app_create`: bütün kurulu modül load olaylarının son indeksi, App creation indeksinden küçük. `test_shutdown_drops_late_callback`: free sonrası teslim yok ve crash yok.
- [ ] D'de seçilmiş backend'i uygula. B: shared App hizmeti ve common dispatch/composition, binding isolation. C: sabit-name probe ve tek binding bağlamı. Universal: mevcut tek giriş; kurulu API kümesi kadar initialize. Üç ayrı production mimarisi ekleme.
- [ ] Eksik binary ile linker/build mismatch'i ayır; mobile request `ERR_UNAVAILABLE`, uninstalled API `null` olsun. Native ID mismatch registration/App başlangıcını durdursun.
- [ ] Task 1 raporundaki komutlarla link/symbol/load testi ve `rtk env GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/run_tests.sh` geçsin. Core değişikliğini ayrı commit et.

## Task 3b: Auth + Firestore üretim build'i — #87

**Files:** `SConstruct`, `tools/build.sh`, `src/auth/`, `src/firestore/`, ilgili descriptor veya register girişleri; `tests/test_native_layout.py`.

- [ ] `test_auth_firestore_share_one_core` ve `test_component_stage_not_overwritten` failing testlerini ekle. API/mock sinyal/metotları aynı kalsın.
- [ ] D'deki platform kararlarına göre Core tek stage, ürün çıktıları ayrı stage olsun. Universal platformda ortak full native bir kez üretilir; split platformda yalnız seçili ürün component'i build edilir.
- [ ] Godot suite ve `rtk python3 -m unittest discover -s tests -p 'test_native_layout.py'`; Android/iOS debug/release build ve 1c Auth+Firestore regression geçsin. Ayrı commit et.

## Task 3c: Diğer üç ürünü aynı sözleşmeye geçir — #88

**Files:** `src/storage/`, `src/database/`, `src/functions/`, ürün entry/descriptor ve build metadata'sı.

- [ ] Her ürünün tekil API/native/metot-sinyal testini yaz; kurulu olmayan ürünün native dependency dışlama beklentisini platform kararına göre assert et.
- [ ] 3b'deki backend'i uygula; yeni genel loader/manifest altyapısı veya modüller arası doğrudan bağımlılık ekleme.
- [ ] Godot suite, üç ürünün debug/release link'i ve full/Auth+Database E2E regression geçsin. Ürün geçişlerini incelemeye uygun ayrı commit'lere al.

## Task 4: iOS export/resource sahipliği — #54

**Files:** `SConstruct`, `tools/build.sh`, `firebase_ios_export_plugin.gd`, `tests/test_ios_package_layout.py`.

- [ ] Split için `test_optional_framework_absent` ve `test_common_framework_owned_once`; universal için ortak native içerik beklentisi açık test olsun.
- [ ] Üretim XCFramework/rpath ve resource sahipliğini 1b raporuna göre uygula. Tek pinned SDK envanterinden resource'ları stage'de tekilleştir; runtime hash-conflict sistemi ekleme.
- [ ] Godot kendi descriptor export yolu yeterliyse özel embedding ekleme. Plist/Auth entitlement seçeneklerini koru.
- [ ] `rtk python3 -m unittest discover -s tests -p 'test_ios_package_layout.py'`, device/simulator export ve signing/archive geçsin; #54 mevcut acceptance korunur.

## Task 5: Altı ZIP ve statik birleşim kanıtı — #67

**Files:** `tools/package.sh`, `tools/firebase_packages.py`, `tests/test_packages.py`, `tests/test_package_import.sh`, subset fixture test tabanı, `tools/run_tests.sh`.
**Interface:** `build_release_archives(stage_root: Path, output_root: Path) -> list[Path]`; spec'teki altı exact dosya adı.

- [ ] Failing `test_shared_paths_byte_identical`, `test_module_paths_disjoint`, `test_full_equals_union`, `test_stale_platform_build_rejected` ve `test_no_game_config_in_release` testlerini yaz.
- [ ] Tek clean component stage'den altı ZIP'i üret. Platform binary/slice veya ID eski/eksikse okunur hata ver; eski üst `modules.txt` yaklaşımını ikinci doğruluk kaynağı olarak tutma.
- [ ] Path ayrıklığı ve ortak SHA256 eşitliğiyle 31 seçimin dosya birleşimini kapsa; 31 headless runtime/import döngüsü kurma.
- [ ] Smoke kümesi beş tekil+full+Auth/Firestore+Auth/Database. Ayrıca ters sırada/tekrar import, tekilden full'a geçiş, Core-only ve modül kaldırmayı doğrula. Bu statik kontroller cihaz E2E yerine geçmez.
- [ ] Fixture tabanı uninstalled mock sınıflarını default arg/preload ile zorunlu kılmasın; `tools/run_tests.sh` eski GDExtension filtresiyle yeni native hata gizlemesin.
- [ ] `rtk python3 -m unittest discover -s tests -p 'test_packages.py'` ve `rtk env GODOT=/Applications/Godot.app/Contents/MacOS/Godot bash tests/test_package_import.sh` geçsin; ayrı commit et.

## Task 6: CI ve release kabulü — #68

**Files:** `.github/workflows/build.yml`, `docs/verification/modular-release.md`.

- [ ] Core/ürün stage'lerini bir release build'inden üret; universal platform full binary'yi tekrar tekrar build etmesin. Altı ZIP ve SHA256SUMS çıkar; platform recipe farklı olabilir.
- [ ] Android SDK/NDK/JDK preflight/cache, generic AAR testi, ID/layout ve import testleri PR/branch akışına girsin. CI build testleri donanım beklemek zorunda değil; native release kabulünde #55/#59 kanıt eksikliği açık kalsın.
- [ ] Artifact/SDK/godot-cpp/toolchain/topoloji girdileri cache'i ayırsın; stale stage tekrar kullanılmasın. Tag publish mevcut yetkili release akışında kalsın; bu plan yayınlama talebi değildir.
- [ ] Son kaynak değişikliklerinden sonra tüm suite ve raporları kontrol et; aynı SDK resource'ları için ayrı runtime collision checker ekleme.

## Task 7: Kullanıcı belgeleri — #91

**Files:** `README.md`, `AGENTS.md`, `docs/verification/modular-release.md`.

- [ ] Altı paket, Core'un dahil oluşu, Auth-only/Auth+Firestore/Auth+Database/full kurulum ve modül kaldırma örneklerini yaz.
- [ ] Platform başına universal/split seçimini ve ölçülmüş boyut bedelini açık anlat. Universal için native ürün dışlaması vaat etme.
- [ ] Eski monolit için clean migration, aynı build tekrar import ve bütün seçili modülleri birlikte upgrade davranışını anlat; modül kayıt/sahiplik yönergelerini güncelle.
- [ ] Plan/spec/kart/file isimleri, kabul testleri ve gerçek doğrulama raporu eşleşsin; doküman değişikliğini ayrı commit et.

## Feedback değerlendirmesi ve tamamlanma

Kabul edilenler: Task 0; bağımsız Android config işi; 1a/1b/1c ayrımı; platform fallback; STL/export/registration-order/interop kontrolleri; ayrı `.gdextension` adayı; tek build_id; native JSON discovery ve 31 runtime kombinasyon testinin kaldırılması; production Core/ilk iki ürün/kalan ürünlerin ayrılması.

Koşullu tutulanlar: Whole-archive gereksinimi ölçülür; full native+seçili Maven çalışacağı varsayılmaz; statik path/hash kanıtı runtime davranışını kanıtlamaz; runtime AppOptions Java resource gereksinimleri sınanmadan seçilmez. Sayısal arşiv/sembol iddiaları kanıt raporunda tekrar ölçülür.

Bu plan ve kartlar uygulama hazırlığıdır. Şimdi Task 0 build'leri, prototipler veya cihaz testleri çalıştırılmadı. İlk yürütülecek işler #56 ve gate'den bağımsız #89'dur. Doğrulanmış altı paket/runtime/export kabulü olmadan uygulama tamamlandı denmez.
