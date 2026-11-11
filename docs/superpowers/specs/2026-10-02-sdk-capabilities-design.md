# Godot Firebase SDK yetenekleri — tasarım

Tarih: 2026-10-02. Kapsam kaynağı: kullanıcının SDK incelemesi sonrası giriş, sorgu güvenliği, Firestore senkronizasyonu, RTDB ve Analytics/Crashlytics/Remote Config için plan ve görev açma isteği.

## Amaç ve sahiplik

Ürün Godot oyunlarının kullandığı yeniden kullanılabilir SDK'dır. SDK; kimlik sağlayıcı köprüleri, veri erişimi, hata sözleşmeleri, senkronizasyon gözlemi ve ürün API'lerini sunar.
Oyun; kayıt şeması, skor doğrulama, para/eşya/ticaret kuralları, çakışma birleştirme politikası ve Firebase backend/erişim kurallarını sahiplenir.
Önceki incelemedeki “ekonomi” oyun ekonomisiydi; Firebase fiyatlandırması değildi. Bu planda cüzdan, mağaza, Cloud Function backend'i veya ekonomik kural motoru uygulanmaz.

Bu teslim planlama ve Agentboard görevleridir. Üretim kodu değişikliği ve cihazda başarılı çalışma iddiası içermez.

## Global constraints

- Godot 4.7.2; Firebase C++ SDK 13.13.0; Firebase iOS SDK 12.19.1.
- Mevcut SDK/godot-cpp pinleri korunur; yeni platform bağımlılıkları uyumluluğu doğrulanarak sabitlenir.
- iOS ve Android üretim hedefidir; macOS editor stub/mock native mobil davranış kanıtı değildir.
- Her ürün GDScript API + mock + native sınıf/platform köprüsü sunar; metot, default argüman, sonuç ve sinyal sözleşmeleri birlikte güncellenir.
- Modüller birbirine doğrudan bağımlı değildir; ortak App ve ana-thread dispatch Core'a aittir.
- Native geçersiz girdide çökmemeli; GDScript okunur hata verir, native aynı sınırı savunur.
- Mobilde eksik native backend sessiz mock'a düşmez; ERR_UNAVAILABLE döndürür.
- Oyun JSON/plist, OAuth ID ve upload kimlik bilgileri reusable AAR/native binary içine gömülmez.
- #90 native topoloji kararı değiştirilmez; #86 Core yaşam döngüsü sahipliği korunur.
- Mevcut #67/#68 altı ZIP kabulü korunur; yeni ürünlerin paket kapsamı #224 takip sürümüdür.
- “Başarılı yerel SDK çağrısı”, “gözlenen yerel snapshot”, “kalıcı disk kaydı” ve “sunucu onayı” birbirinin yerine kullanılmaz.

## Yaklaşım

Mevcut API'leri genişletmek tercih edildi. Toplu adapter yeniden yazımı gerekmiyor; callback/thread/load düzenini çoğaltan ikinci altyapı kurulmayacak.
Analytics ve Remote Config pinned C++ SDK üzerinden uygulanır. Crashlytics'in pinned C++ dağıtımında normal ürün arşivi yoktur; Android Java/NDK ve iOS Objective-C++ köprüleri gerekir.
Her ürün geliştirme sırasında mevcut native düzende derlenebilir. Birlikte kurulabilir release kabulü ilgili #90/#85/#86/#67/#68 sonuçlarını bekler; bu gate API/mock geliştirmesini bloklamaz.

## A — Girdi ve kimlik güvenliği

Kartlar: #211 sorgu güvenliği, #212 auth işlem kontrolü, #213 auth mock, #214 döngüsel girdi; mevcut #58 Google ve yeni #215 Play Games.

- Query kombinasyonları ile __name__ değer/operator kuralları pinned Firestore SDK'dan türetilir. İki != filtresi ve sayısal belge ID'si SDK'ya ulaşmadan ERR_INVALID_ARGUMENT olur.
- Functions/ortak Variant dönüşümü aktif recursion yolundaki cycle'ı reddeder. Genel container derinliği 100 ile sınırlıdır; ürüne özgü daha dar kurallar korunur. Paylaşılan ama döngü oluşturmayan alt nesneler kabul edilir.
- Link başlangıcında User/UID ve auth işlem nesli yakalanır. Sign-out/hesap değişimi/shutdown gecikmiş callback'i geçersiz kılar.
- İkinci eşzamanlı credential UI isteği yeni ERR_BUSY=-6 döndürür; FirebaseResult ve native outcome sabitleri birlikte güncellenir. Sign-out engellenmez, bekleyen işlem ERR_CANCELLED ile sonlanır.
- Her task bir kez tamamlanır. Credential çakışmasında hata korunur; hesap veya oyun verisi otomatik birleştirilmez.
- Mock oturumsuz token/delete için ERR_NO_USER üretir; aynı mock sağlayıcı hesabı aynı UID'yi verir.

### Login arayüzleri

Yeni `sign_in_with_google() -> FirebaseTask`, `link_with_google() -> FirebaseTask`.
Android Credential Manager; iOS GoogleSignIn ve URL callback/scheme. Firebase oturumu mevcut C++ Auth'ta açılır, platform köprüsü credential edinir.
Oyun ayarları `firebase/auth/google_web_client_id` ve `firebase/auth/google_ios_client_id`; uygun değerler oyunun JSON/plist'inden türetilebilir. Başarısız giriş mevcut oturumu değiştirmez; iptal ERR_CANCELLED'dır.

Yeni `sign_in_with_play_games_platform() -> FirebaseTask`, `link_with_play_games_platform() -> FirebaseTask`.
İsteğe bağlı Android PGS v2 helper, oyun ayarlarından app ID ve Web OAuth client ID alıp taze server auth code edinir. Kod saklanmaz/loglanmaz.
Mevcut `sign_in_with_play_games(server_auth_code: String)` ve link API'leri korunur. #60 oyun entegrasyonu olarak kalır.
Apple/Game Center iOS API'leri korunur. Apple Android OAuth bu dalgada yoktur; iOS↔Android ortak giriş Google ile sağlanır. SDK açılışında koşulsuz anonim giriş veya ayrı token/UID dosyası eklenmez.

## B — Firestore senkronizasyon gözlemi

#216 arayüzleri:

```gdscript
get_doc(path: String, source: String = "default") -> FirebaseTask
query(collection_path: String, filters: Array = [], order_by: Array = [],
      limit: int = 0, source: String = "default") -> FirebaseTask
query_snapshot(collection_path: String, filters: Array = [], order_by: Array = [],
               limit: int = 0, source: String = "default") -> FirebaseTask
listen_doc(path: String, callback: Callable, include_metadata_changes: bool = false) -> int
set_network_enabled(enabled: bool) -> FirebaseTask
wait_pending_writes() -> FirebaseTask
```

source tam olarak default/cache/server değerlerinden biridir. query() mevcut Array sonucunu korur.
Document snapshot mevcut alanlarına `metadata: {is_from_cache: bool, has_pending_writes: bool}` ekler.
query_snapshot() sonucu `{documents: Array, metadata: Dictionary}`; boş query'de de metadata vardır.
Native/backend run_query adı korunur; run_query_snapshot eklenir.

Write task başarı sonucu sunucu ACK'idir. Offline yazma pending kalabilir. Yerel listener snapshot'ı disk fsync/kalıcı commit garantisi değildir.
wait_pending_writes çağrı anında aktif kullanıcının bekleyen yazmalarını (önceki oturumdan kalıcı kuyruk dahil) kapsar; sonraki yazmaları kapsamaz; kullanıcı değişiminde hata verir.
Network-control tamamlanması gerçek internet bağlantısı anlamına gelmez. Mobil varsayılan Firestore persistence ve process-restart davranışı cihazda doğrulanır.

#65 nested query/order mock davranışını, #70 timestamp sınırlarını düzeltir. #71 isteğe bağlı bounded-wait tasarımı backlog'da kalır; timeout yalnız ilgili waiter'ı bitirebilir, alttaki task/yazmayı iptal edemez veya geç ACK'i atamaz.
Cursor sayfalama #73 ve koşullu transaction #74 mevcut backlog işleridir; bu dalganın kritik yolu değildir.

## C — Realtime Database

#217: optional startup setting `firebase/database/persistence_enabled: bool=false`.
Core autoload bu ayarı bir kez okuyup backend `initialize(persistence_enabled: bool=false) -> Error` çağrısına aktarır.
SDK persistence ayarı ilk DatabaseReference/listener öncesinde uygulanır. Runtime setter yoktur; değişiklik sonraki başlangıçta etkilidir.
Public `set_network_enabled(enabled: bool) -> FirebaseTask` SDK GoOnline/GoOffline komut sonucudur.

#218: mevcut get_value/listen_value yalnız tam özel yollar `.info/connected` ve `.info/serverTimeOffset` için okuma istisnası sağlar. Normal ve OnDisconnect yazmaları bu yolları reddeder.

```gdscript
on_disconnect_set_value(path: String, value: Variant) -> FirebaseTask
on_disconnect_update_children(path: String, values: Dictionary) -> FirebaseTask
on_disconnect_remove_value(path: String) -> FirebaseTask
on_disconnect_cancel(path: String) -> FirebaseTask
```

Task başarıları server registration/cancel ACK'idir, disconnect eyleminin yürüdüğü anlamına gelmez.
Her reconnect'te oyun yeniden registration yapar. Örnek akış önce registration ACK, sonra bağlantı başına online kaydı gösterir; global oyuncu state politikası veya otomatik replay eklenmez.
.info/connected yalnız bu SDK bağlantısını belirtir. #66 kök değer/boş parent mock düzeltmesini sahiplenir.
Persistence ile OnDisconnect ayrı özelliklerdir; presence persistence gerektirmez.

## D — Analytics

#219, `Firebase.analytics` / `FirebaseAnalyticsNative`:

```gdscript
log_event(name: String, parameters: Dictionary = {}) -> FirebaseTask
set_user_id(user_id: String) -> FirebaseTask
clear_user_id() -> FirebaseTask
set_user_property(name: String, value: String) -> FirebaseTask
clear_user_property(name: String) -> FirebaseTask
set_collection_enabled(enabled: bool) -> FirebaseTask
set_consent(consents: Dictionary) -> FirebaseTask
reset_analytics_data() -> FirebaseTask
```

İlk event parametre tipleri String/int/finite float. İsim, reserved-name, sayı ve boyut kuralları pinned SDK ile eşleşir.
Consent anahtarları analytics_storage/ad_storage/ad_user_data/ad_personalization; değerler GRANTED/DENIED sabitleridir. Verilmeyen anahtarlar değiştirilmez.
Başarı yerel SDK çağrısıdır; collection kapalı olduğunda event'in saklandığını/teslim edildiğini söylemez. İkinci offline kuyruk yoktur.
Auth user_id otomatik atanmaz. Optional export collection ayarı verilmemişse pinned SDK varsayılanı korunur; açık true/false ayarı Manifest/Info.plist'te startup öncesi uygulanır. Runtime/persisted override davranışı ayrıca belgelenir.
Bugünkü Android koşulsuz Analytics Maven bağımlılığı ayrıca incelenir; klasör kaldırma native dışlama veya collection kapanması diye sunulmaz.

## E — Remote Config

#220, `Firebase.remote_config` / `FirebaseRemoteConfigNative`:

```gdscript
ensure_initialized() -> FirebaseTask
set_defaults(values: Dictionary) -> FirebaseTask
set_settings(minimum_fetch_interval_ms: int, fetch_timeout_ms: int) -> FirebaseTask
fetch() -> FirebaseTask
activate() -> FirebaseTask
fetch_and_activate() -> FirebaseTask
get_value(key: String, value_type: int = TYPE_STRING) -> FirebaseTask
get_info() -> FirebaseTask
```

get_value tipleri BOOL/INT/FLOAT/STRING/PACKED_BYTE_ARRAY; sonuç `{value, source: STATIC|DEFAULT|REMOTE, conversion_successful: bool}`.
Defaults scalar/bytes'tır; aggregate değerler reddedilir. activate/fetch_and_activate bool changed döndürür.
get_info sonucu `{last_fetch_time_ms: int, last_fetch_status: int, last_fetch_failure_reason: int, throttled_end_time_ms: int}`; enum eşlemeleri public sabitlerle belgelenir.
Fetch fetched state'i günceller, aktif state'i değiştirmez. Fetch success yeni HTTP isteği garantisi değildir. Cold-start, varsayılan/fetched/active ayrımı mock'ta korunur.
Module loader remote_config için tested explicit mapping/PascalCase ile FirebaseRemoteConfigNative'i bulur; module.capitalize() tek başına kullanılmaz.

#221:

```gdscript
start_listening() -> FirebaseTask
stop_listening() -> void
signal config_updated(updated_keys: PackedStringArray)
signal config_update_failed(error_code: int, message: String)
```

Tek listener/module, idempotent start. Olay otomatik fetch edilen değişiklikleri bildirir; activate etmez. Stop/teardown sonrasında callback bastırılır; sinyaller Core'dan ana thread'e gider. Yapılandırmayı oyuna uygulama anı oyunun kararıdır.

## F — Crashlytics

#222 Android/ortak API, #223 iOS/semboller. `Firebase.crashlytics` / `FirebaseCrashlyticsNative`.

```gdscript
log_message(message: String) -> FirebaseTask
set_custom_key(key: String, value: Variant) -> FirebaseTask
set_user_id(user_id: String) -> FirebaseTask
clear_user_id() -> FirebaseTask
record_error(name: String, message: String, stack: Array[Dictionary] = []) -> FirebaseTask
set_collection_enabled(enabled: bool) -> FirebaseTask
is_collection_enabled() -> FirebaseTask
did_crash_previous_execution() -> FirebaseTask
check_unsent_reports() -> FirebaseTask
send_unsent_reports() -> FirebaseTask
delete_unsent_reports() -> FirebaseTask
```

Stack frame `{function: String, file: String, line: int}` (`get_stack()` karelerinin `source` anahtarı `file` sayılır); custom key String/bool/int/finite float.
Açık GDScript nonfatal raporları ve platform native crash yakalama desteklenir; bütün Godot hataları otomatik yakalanmış sayılmaz.
Yerel log/nonfatal/send/delete sonucu server ACK değildir. Collection açıkken unsent kontrolü false ile tamamlanır; platform callback farkları public task'ı asılı bırakmaz.
Startup collection seçeneği verilmemişse pinned platform varsayılanı korunur; explicit false taze kurulumda App/otomatik başlangıçtan önce export metadata'sıyla uygulanır. Runtime override'ın etki zamanı/platform kalıcılığı belgelenir.
Analytics veya Auth zorunlu modül bağımlılığı yoktur. Analytics breadcrumb opsiyoneldir.
Android Gradle/NDK build-ID kaynakları oyun export sırasında üretilir; runtime JSON yaklaşımının bunları kendiliğinden sağladığı varsayılmaz.
Native crash kabulü için Android unstripped .so + GNU build ID/R8 mapping; iOS eşleşen UUID/dSYM ve upload akışı gerekir. SDK production API'sine crash() eklenmez.
Godot engine frame'leri yalnız eşleşen engine sembolleri varsa vaat edilir. Console/device eksikliği kabulü açık bırakır.

## G — Release ve doğrulama

#69 mevcut beş ürün üstünde başlayıp yeni modüllerle sekiz ürüne genişleyen ClassDB/mock signature gate'idir. Missing stub skipped olur.
#55/#59 var olan cihaz sahipliğini korur; auth/sync senaryoları ilgili özelliklerin fazında eklenir. Erken #90 architecture kanıtı yeni ürünlerin bitmesini beklemez.
#224 takip release'inde üç yeni tekil ZIP ve sekiz ürün full vardır: toplam dokuz ZIP, ayrı Core ZIP yok. Mevcut altı-paket hedefi geriye dönük değiştirilmez.
Her modül kendi development build/export kaydını yapar; ortak dosya değişiklikleri sıralanır. Final takip release; byte equality, path ayrıklığı, full=union, stale/mixed build reddi, oyun config dışlama ve symbol provenance kurallarını sürdürür.
255 alt kümenin native build'i yerine statik ayrıklık + hedefli import smoke kullanılır.

## Doğrulama tabanı ve kapsam dışı

2026-10-02 incelemesinde Godot 4.7.2 altında sekiz GDScript suite ve Android AAR testi geçti; mobil Firebase runtime kabulü yoktur. Plan hazırlığında üretim testi yeniden çalıştırılması gerekmez; kod değişmedi.
Bu dalgaya App Check, AdMob, Billing, FCM, Apple Android OAuth, oyun ekonomi backend'i veya otomatik conflict resolver eklenmez. Storage #72, pagination #73 ve koşullu transaction #74 ayrı backlog işleri olarak kalır.

## Birincil kaynaklar

- [Google Android](https://firebase.google.com/docs/auth/android/google-signin), [Google iOS](https://developers.google.com/identity/sign-in/ios/start-integrating), [PGS server access](https://developer.android.com/games/pgs/android/server-access).
- [Firestore C++](https://firebase.google.com/docs/reference/cpp/class/firebase/firestore/firestore), [RTDB persistence](https://firebase.google.com/docs/reference/cpp/class/firebase/database/database), [disconnect handler](https://firebase.google.com/docs/reference/cpp/class/firebase/database/disconnection-handler).
- [Analytics C++](https://firebase.google.com/docs/reference/cpp/namespace/firebase/analytics), [Remote Config C++](https://firebase.google.com/docs/remote-config/cpp/get-started).
- [Crashlytics Android NDK](https://firebase.google.com/docs/crashlytics/android/get-started-ndk), [iOS symbolication](https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports).

Public belgelerdeki yeni sürüm numaraları pinleri kendiliğinden değiştirmez; uygulamada pinned header/source esas alınır.

