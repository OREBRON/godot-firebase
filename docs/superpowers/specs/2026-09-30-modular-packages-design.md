# Godot Firebase: Birlikte kurulabilen modül paketleri

Durum: Geri bildirim sonrası revize edilmiş tasarım önerisi. Boyut, native topoloji ve Android konfigürasyon tercihleri aşağıdaki ölçüm/kanıt görevlerinden sonra kesinleşir. Henüz native çalışma veya boyut tasarrufu doğrulanmış değildir.

## İstenen sonuç

Bir release altı kullanıcı paketi sunar:

| Paket | İçerik |
| --- | --- |
| `godot-firebase.zip` | Ortak dosyalar ve beş modül |
| `godot-firebase-auth.zip` | Ortak dosyalar ve Auth |
| `godot-firebase-firestore.zip` | Ortak dosyalar ve Firestore |
| `godot-firebase-storage.zip` | Ortak dosyalar ve Storage |
| `godot-firebase-database.zip` | Ortak dosyalar ve Realtime Database |
| `godot-firebase-functions.zip` | Ortak dosyalar ve Functions |

“Stage”, mevcut modül listesine göre Storage olarak yorumlanmıştır. Her tek modül ZIP'i kendi başına kurulabilir; ayrıca Core indirme adımı gerekmez. Aynı release'in ortak yolları aynı baytları içerir; modüle özgü yollar birbirinden ayrıdır. Auth sonra Firestore kurulması ile Firestore sonra Auth kurulması aynı dosya kümesini üretir. Tam paket bu bileşenlerin birleşimidir, farklı bir ikinci uygulama değildir.

Kullanıcıdan oyun kombinasyonu için eklenti native kodunu derlemesi istenmez. Altı paketin kullanıcı deneyimi Android/iOS iç mimarisinden bağımsızdır. Native binary boyutunu en aza indirmek artık kanıtlanmış gereksinim olarak varsayılmayacak; ölçülen fark ve bakım bedeli birlikte değerlendirilecektir.

## Korunan sınırlar

- Godot 4.7.2, Godot API 4.7.
- Firebase C++ SDK 13.13.0, Firebase iOS SDK 12.19.1; `tools/versions.env` tek sürüm kaynağıdır.
- iOS minimum 15.0; device arm64 ve simulator arm64.
- Android arm64-v8a; SDK platform 35 ve mevcut NDK düzeni.
- macOS arm64 editör stub'ı ve masaüstü mock davranışı korunur. Masaüstü Firebase, Web, yeni Firebase ürünleri kapsam dışıdır.
- `Firebase.auth`, `Firebase.firestore`, `Firebase.storage`, `Firebase.database`, `Firebase.functions` API'leri korunur.
- Eksik modül özelliği `null`; mobil native hatası sessiz mock yerine `ERR_UNAVAILABLE` üretir.
- Native input savunması, mock/native metot ve sinyallerin uyumu, ana thread üzerinden sinyal teslimi korunur.
- Oyuna ait JSON/plist ve üretilmiş oyun konfigürasyonu release paketlerine girmez.
- Kurulu bileşenler tek immutable `build_id` ile eşleşir; platforma göre farklı topoloji seçilebilir.

## Mevcut durum ve geri bildirim kanıtı

Bu depo MCP proje listesinde yok; coverage kontrolü `project not found or not indexed` döndürdü. Bulgular ilgili kaynakların doğrudan okunmasına dayanır.

- `SConstruct` seçilen Firebase arşivlerini tek `libgodot_firebase` çıktısına bağlar; eski tek modül paketleri native düzeyde üst üste eklenemez.
- `tools/build_android_aar.sh` oyun JSON'unu native build sırasında AAR'a gömer; prebuilt dağıtım için bu bağ kaldırılmalıdır.
- `src/core/firebase_app_native.cpp` Android'de şu an `App::Create(jni_env, activity)` kullanır. Pinned `firebase/app.h` içinde `LoadFromJsonConfig` ve explicit `AppOptions` alan `Create` overload'u bulunur; bu, Java tarafındaki resource gereksinimlerini ortadan kaldırdığını kanıtlamaz.
- Pinned godot-cpp `tools/android.py`, `clang++` ile link eder; bu dosyada açık `-static-libstdc++` seçimi görülmedi. Gerçek STL sonucu link komutu ve ELF üzerinden kontrol edilecektir.
- Yerel Firebase arşivinde `FirebaseCoreExtension`, Auth/Firestore/Functions/Storage klasörlerinde; `FirebaseAppCheckInterop` beşinde; `FirebaseSharedSwift`, Database/Firestore/Functions klasörlerinde; `FirebaseAuthInterop`, Auth/Functions/Storage klasörlerinde bulunuyor. Bunlar ortak sahiplik adaylarıdır; tüm closure'ın tamamlandığı iddia edilmez.
- Geri bildirimdeki 2.8 MB, global/undefined sembol sayıları ve zorunlu whole-archive iddiası bağımsız ölçülmüş sonuç olarak alınmadı; görevlerde doğrulanacak hipotezlerdir.

## Karar sırası

1. **Boyut ölçümü:** Aynı fixture oyunda mevcut Auth-only ve full release çıktılarının stripped native, compressed APK/IPA, uncompressed uygulama ve bağımlılık boyutları karşılaştırılır. iOS dead-strip ve Android strip/section-GC link komutları kaydedilir. Full native + yalnız Auth Maven seçimi ayrıca çalıştırılıp denenir; klasik full-vs-Auth karşılaştırması native farkı Java farkından ayıramaz.
2. **Android konfigürasyonu:** Native bölünmeden bağımsız olarak JSON build aşamasından çıkarılır. Önce runtime `AppOptions` yolu denenir. Resource kullanan Java/Firebase bileşenleri nedeniyle başarısızsa export-time resource AAR kullanılır.
3. **Topoloji kanıtı:** Ayrı `.gdextension` ve özel-loader adayları ucuz Android ELF/load testiyle karşılaştırılır; sonra iOS link/ObjC sahipliği ve erken Auth+Firestore cihaz E2E gelir. Database/Storage/Functions ve production export final regression'ı üretim geçişinden sonradır; mimari kararını bu sonraki görevlerin tamamlanmasına bağlayarak döngü oluşturulmaz.
4. **Platform kararı:** Boyut/bakım raporu ve çalışan prototiple platform başına tek native backend seçilir. Tek ortak binary, Android'de düşük ölçülen native fark ve seçili bağımlılıklarla düzgün çalışma hâlinde ciddi adaydır; küçük paket hedefiyle ilgili değişen beklenti kullanıcıya açıkça sunulur.

Ölçülmemiş bir “önemsiz boyut” eşiği veya otomatik MiB bütçesi icat edilmez. Ölçüm çıktısı mutlak farkı ve yüzde farkını verir; seçim raporunda gerekçe yazılır. Platform topolojisi üretim koduna geçmeden inceleme için sunulur. Bu plan ölçümleri şimdi çalıştırma veya uygulama koduna başlama talebi değildir.

## Native adaylar

### A: Ortak universal native backend

Bir kez derlenen tüm native ürünler ortak dosyalarda bulunur; modül ZIP'leri API/mock/metadata katmanlarını ekler. Kurulu olmayan API başlatılmaz; export yalnız gereken Maven ürünlerini ve gerçek transitive closure'ı eklemeyi dener. Tüm native ürünlerin Java callback/static initialization gereksinimleri buna izin vermiyorsa “seçili Maven” avantajı varsayılmaz. Gerekli tüm Java ürünlerini taşımak kullanıcıya açık boyut/bağımlılık bedelidir.

Bu aday custom loader gerektirmez; kullanılmayan native ürünleri de taşıyabilir. Bir platformda kabul edilirse tam ve tek modül paketleri yine aynı ortak binary'yi içerir. Seçilmeyen native binary'lerin tamamen yokluğu o platformun kabul kriteri olmaktan çıkar; GDScript modül seçimi korunur.

### B: Her modüle ayrı `.gdextension`

Core yalnız ortak Firebase App/state sahipliğini sağlar. Her modül Godot'un kendi `.gdextension` girişini kullanır; Android `DT_NEEDED`, iOS `@rpath` ile Core'a bağlanır. Her binding'in kendi godot-cpp sembolleri hidden/export-list ile izole edilir. Core'un custom Godot sınıfından başka binding'de doğrudan miras alma varsayılmaz; ortak request/sinyal davranışı Core'daki hizmete composition/delegation veya uygun bir C arayüzüyle taşınır. `FirebaseModuleNative` ana thread tesliminin sahibi kalır; aynı iş kuralı beş yerde kopyalanmaz.

Bu aday özel loader/export embedding ihtiyacını azaltabilir, fakat kayıt sırası, instance-binding token'ları, temel sınıf sınırı, callback payload/nesne sahipliği ve shutdown testle kanıtlanır. Ayrı `.gdextension` varlığı otomatik bir dependency load-order garantisi sayılmaz. Önce bu aday sınanır; mevcut base class'ı koruma tercihi tek başına elenme gerekçesi değildir.

### C: Tek Core GDExtension ve özel native loader

Core tek godot-cpp kayıt bağlamını ve ortak base class'ı sahiplenir. Beş bilinen modül binary adı platform loader'ıyla denenir; native taraf JSON manifest veya `res://` parse etmez. GDScript kurulu modülleri bulur, native tarafta yüklenen küme ile eşleştirir. Yok dosya opsiyonel olabilir; var dosyada unresolved symbol/build mismatch “modül yok” diye gizlenmez.

Modül girişi kalıcı minimal C imzasıyla `godot_firebase_<module>_build_id() -> const char *` ve `godot_firebase_<module>_register() -> void` sunar. Build ID eşitliği kontrol edilmeden sınıf kayıt callback'i çalıştırılmaz. Platform embedding/signing ve loader arama yolu ayrıca kanıtlanır. Bu aday, B'nin başarısız olduğu veya daha fazla iş gerektirdiği gösterilirse değerlendirilir.

## Her split adayın zorunlu invariant'ları

- Bütün kurulu modül library'leri ve SDK registration/static initializer'ları, Firebase App yaratma/configure işleminden **önce** tamamlanır. Bu kural C++ `App::Create` ve Java/Objective-C tarafındaki default App oluşturmayı birlikte kapsar. Android `FirebaseInitProvider` zamanlaması ayrıca incelenir.
- Core'da tek `firebase_app` state ve token callback registry bulunur. Aynı `App*` görmek tek başına yeterli kabul edilmez.
- Android'de Firebase/C++ nesneleri paylaşan bütün DSO'lar uyumlu tek `libc++_shared.so` kullanır; Godot engine ve diğer AAR'larla runtime/version/package çakışması kontrol edilir. Her DSO'ya ayrı static libc++ gömülmez.
- Core export listesi ve module imports birbiriyle eşleşir. godot-cpp sembolleri B'de izole, C'de Core'dan bilinçli paylaşılmıştır. ELF version script ve Mach-O exported-symbols listesi raporda yer alır.
- `firebase_app` arşivinin bütün objelerini dahil etme ihtiyacı import closure/link map ile belirlenir. Android'de archive-scoped whole-archive veya dar force-reference/export; iOS'ta dar `-force_load` seçenekleri ölçülür. Bütün SDK için körlemesine whole-archive yapılmaz. Dahil etme ve görünürlük/export ayrı kararlardır.
- iOS ortak sahiplik envanteri yukarıdaki dört interop/Swift adayı ve mevcut Core listesinden başlar; modül closure'ına göre başka ortak framework'ler de bulunur. Aynı ObjC/Swift implementasyonu iki dylib'de kalmaz. Release linker strip sonrası initializer ve registrar'ların korunması kontrol edilir.
- Runtime hot unload yoktur; module library'leri process bitmeden unload edilmez. Listener/callback kullanıcıları temizlenir, sonra App kapatılır.

## Paket metadata ve sahiplik

`addons/firebase/core/package.json` ve `addons/firebase/<module>/package.json` yalnız `build_id` ve `module` uyumluluk alanlarını taşır. Platform binary/resource yolları gerekiyorsa veri alanlarıdır; ayrı schema/ABI/SDK version karşılaştırması eklenmez. SDK/toolchain bilgisi tek release provenance dosyasında tutulur.

`build_id`, tüm platform ve parçalar için bir kez, kaynak commit'i ve pinned SDK hash'leri/godot-cpp commit'i/toolchain/build-recipe girdilerinden üretilir. Release tag'i display/provenance bilgisidir; tag tek başına immutable uyumluluk anahtarı sayılmaz. Aynı ID manifest ve binary'ye gömülür. Geçerli mixed-release kontrolü export preflight'ında ve native kayıt/App initialize öncesinde vardır; bypass edilmiş eski dylib constructor'larının hiç side-effect üretmeyeceği vaat edilmez.

Core dosyaları bir kez stage edilir; modül build'leri bunları değiştirmez. Modül yolları kendi klasörlerinde ayrıdır. `bin/modules.txt` yerine kurulu modül manifestleri GDScript/export tarafından keşfedilir. Core-only ve modül silme desteklenir. Upgrade, bütün seçili paketleri aynı build'den kurmayı gerektirir.

## Android konfigürasyon kararı

İlk tercih oyun JSON'unu runtime'da doğru package client'a indirgemek, explicit AppOptions ile tek default App yaratmaktır. Birden fazla client, package mismatch, API key/app ID, native Java instance ile aynı App, restart ve token değişimi test edilir. `FirebaseInitProvider`, resource okuyan Java API'leri, `default_web_client_id` ve mevcut giriş sağlayıcıları gereksinimleri incelenir. Provider daha erken App oluşturuyorsa library load-before-create invariant'ı sağlanacak manifest/bridge düzeni kanıtlanır.

Bu yol tüm mevcut modüllerde çalışırsa XML converter ve geçici config AAR yapılmaz. Başarısızsa pinned SDK converter'ın XML field/escaping/keep semantics'ini veren GDScript converter ve export-time yalnız-resource AAR kullanılır. İki üretim config yolu birlikte sürdürülmez. Her iki durumda generic bridge AAR oyun bilgisi içermez, oyun başına native/Java bridge build'i gerekmez.

## Test ve fallback

Paket ayrıklığı/eşitliği path+SHA256 kontrolü bütün alt kümelerin **dosya birleşimini** kapsar; runtime uyumunu kanıtlamaz. Smoke kümesi beş tekil, full, Auth+Firestore ve Auth+Database'dir. Ters import, tekrar import, Core-only ve modül kaldırma ayrıca test edilir. Aynı SDK resource'larının sahipliği build-time envanterde tekilleştirilir; runtime/export için ayrı bundle hash-conflict sistemi kurulmaz.

- Android ELF/load kanıtı başarısızsa aynı adayın iOS deneyi durur. Diğer aday ayrı ucuz Android testinden geçebilir; Android'in bağımsız native yetersizliği iOS'u evrensel olarak imkânsız kılmaz.
- Android universal, iOS split veya tersi geçerli fallback'tir; kullanıcı paket formatı aynı kalır. Platform karar raporu hangi bedeli getirdiğini açıklar.
- B başarısızsa C; C başarısızsa universal aday değerlendirilir. Her aday mevcut modül davranışı/config/oturum paylaşım testlerinden geçmek zorundadır.
- Universal farkı kabul edilmez ve hiçbir split aday çalışmazsa **native yeniden düzenleme** durur. Android generic config ve statik paketleme işleri ilerleyebilir; çalışan modüler release, 31 kombinasyon paketi veya kullanıcıda yeniden derleme çözümü varmış gibi gösterilmez.
- Cihaz erişimi yoksa sonuç “doğrulanmamış” kalır; link/mock başarısı native E2E yerine kullanılmaz.

## Kabul ölçütleri

Altı ZIP tek başına/birlikte kurulabilir; tam ZIP dosya birleşimiyle aynı olur. Tek Core/autoload vardır. Build mismatch okunur hata verir. Modül kaldırılınca API `null` ve export envanteri güncel olur. Native dışlama/boyut beklentisi seçilen platform kararıyla uyumludur ve belgede açık yazılır. Android/iOS'ta Auth oturumu UID-korumalı Firestore/Database isteklerinde, sign-out sonrası erişim reddiyle birlikte doğrulanır. Ana thread callback ve shutdown güvenliği korunur. Release ZIP'leri oyun konfigürasyonu taşımaz.

## Kaynaklar

- [Android NDK C++ runtime kuralları](https://developer.android.com/ndk/guides/cpp-support): direct clang++ default'u ve çok-DSO/STL sınırları; AAR/middleware uyarıları da dikkate alınır.
- [Firebase Unity ayrı kurulum](https://firebase.google.com/docs/unity/setup-alternative).
- [Unity universal native seçenekleri](https://github.com/firebase/firebase-unity-sdk/blob/main/CMakeLists.txt).
- [Godot GDExtension export bağımlılıkları](https://docs.godotengine.org/en/4.4/tutorials/scripting/gdextension/gdextension_file.html).

Bu kaynaklar planın değerlendirme dayanağıdır; adayların bu projede çalıştığını kanıtlamaz.
