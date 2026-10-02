# Godot Firebase SDK Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Godot 4.7.2 SDK'sının güvenli login/sorgu, gözlenebilir çevrimdışı senkronizasyon ve Analytics/Crashlytics/Remote Config arayüzlerini tamamlamak.

**Architecture:** Mevcut GDScript API/mock/native modül düzeni additive olarak genişler. Ortak App/dispatch Core'da kalır; oyun politikaları SDK'ya taşınmaz. Analytics/Remote Config C++, Crashlytics platform köprüleri üzerinden çalışır.

**Tech Stack:** Godot 4.7.2, GDScript, C++/GDExtension, Firebase C++ 13.13.0, Firebase iOS 12.19.1, Android Java/JNI, iOS Objective-C++.

**Spec:** [SDK capability design](../specs/2026-10-02-sdk-capabilities-design.md)

## Global Constraints

- Godot 4.7.2; Firebase C++ SDK 13.13.0; Firebase iOS SDK 12.19.1.
- GDScript/mock/native aynı metot/default/result/sinyal sözleşmesine uyar; native validation ve Core ana-thread dispatch korunur.
- Oyun JSON/plist/OAuth/config ve upload kimlik bilgileri reusable prebuilt içine gömülmez.
- Oyun ekonomisi backend'i, kayıt şeması ve otomatik conflict/account merge kapsam dışıdır.
- Mobil eksik native ERR_UNAVAILABLE; desktop mock/stub cihaz başarı kanıtı değildir.
- #90 platform topolojisi seçilmez; #86 Core sahipliği ve mevcut #67/#68 altı-paket kilometre taşı korunur.
- Yeni ürünlerin final dokuz-paket kabulü #224'tür; API/development build çalışması final topoloji gate'inden bağımsız ilerleyebilir.
- Geliştirme branch/worktree başlatılırken repository yönergelerine uyulur. Bu planlama tesliminde kod veya branch/commit oluşturulmadı.

## Review Focus

- Yanlış sıradaki auth UI callback'i: #212 yanlış UID'ye bağlamayı ve çift task tamamlamayı reddeder.
- Offline yazma henüz ACK almadan process ölümü: #216/#217 pending snapshot, persistence ve eventual acknowledgement'ı ayırır.
- Cache boşluğu veya yalnız metadata değişimi: #216 boş query metadata'sını ve listener opt-in'i korur.
- İlk açılış veya runtime collection değişimi: #219/#222/#223 pre-start export ayarı ile persisted override farkını test eder.
- Reconnect/shutdown/symbol mismatch: #218/#221 callback ömrünü, #223 yanlış binary sembollerinin teşhis edilmesini test eder.

## Board ve çalışma sırası

- Epic **#206**: güvenli girdiler ve giriş. Yeni #211–#215; mevcut #58/#55/#59.
- Epic **#207**: veri senkronizasyonu. Yeni #216–#218; mevcut #65/#66/#70. #71 koşullu backlog'da.
- Epic **#208**: yeni ürünler. Yeni #219–#224; mevcut #69.
- İlk dalga #211/#212/#213/#214 ve #65/#66/#70; #69 mevcut beş üründe paralel kurulabilir.
- Sonraki dalga #58/#215 ile #216 ve #217→#218 bağımsız modül sahipleriyle ilerler.
- Yeni ürünlerde #219, #220→#221 ve #222→#223 paralel sorumluluk alanlarıdır.
- Core/registry/SConstruct/bootstrap/export ortak dosyalarını aynı anda farklı worker'lar değiştirmez; bu dokunuşları koordinatör sırayla entegre eder.
- Son cihaz/release kabulü #55/#59 ve #224. Erken #90 kararına bağımlılık döngüsü eklenmez.
- #72 Storage, #73 cursor, #74 koşullu transaction ve #75 kural örnekleri mevcut backlog'da kalır. AdMob/App Check/Billing/FCM/Apple Android OAuth için bu istekte yeni task açılmadı.

## Uygulama ve doğrulama protokolü

Her kart başlamadan güncel body okunur ve `todo -> doing` beklenen durumla claim edilir. Bitmiş veya başka sahibin doing kartı devralınmaz.
Aşağıdaki her görev kendi failing-test→implementation→passing-test→review döngüsünü taşır. Oyun dışı mock yardımcıları test fixture'ıdır; SDK production API'sine sızmaz.
Ortak GDScript kontrolü:

```bash
rtk env GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/run_tests.sh
rtk env ANDROID_HOME=/Users/ozan.yildiz/Library/Android/sdk bash tests/test_android_aar.sh
```

Android yolu örnek yerel host yoludur; CI kendi ortamını sağlar. AAR kontrolü bridge/export değişen görevlerde koşulur. Seçili native build'ler mevcut `tools/build.sh --modules ... --platforms ...` arayüzüyle, pinlere uygun kurulu toolchain kullanılarak doğrulanır.
Başarı: ilgili suite exit 0 ve beklenen test sonuçları; script error/hang failure sayılır. Cihaz senaryoları ayrıca gerçek Firebase kanıtı ister.
Her görev sonunda dar diff review ve bağımsız commit yapılır; task yalnız kendi kabulü kanıtlandıysa done'a geçer. Henüz eklenmemiş modül/test dosyaları aşağıda **yapılacak** dosyalardır.

---

### Task #211: Sorgu girdi güvenliği

**Epic:** #206. **Dependencies:** Bağımsız; #63 tamamlanmış temel korunur.

**Files:** `addons/firebase/firestore/firebase_firestore.gd`, `addons/firebase/firestore/firebase_firestore_mock.gd`, `src/firestore/firebase_firestore_native.cpp`, `tests/test_firestore_mock.gd`.

**Interfaces:** Mevcut query(filters, order_by, limit) sözleşmesi; yeni public metot yok.

- [ ] **Step 1 — Regression/spec testi:** test_duplicate_not_equal_rejected ve test_invalid_document_id_rejected: task ERR_INVALID_ARGUMENT; backend çağrılmamış. Geçerli belge-ID ve filtre kombinasyonu karşı testleri başarılı.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Pinned SDK predicate kombinasyonlarını GDScript/native sınırlarına uygula; exception yakalamayı tek savunma yapma.
- [ ] **Step 4 — Doğrulama:** İlgili mock suite + doğrudan native invalid-input mobil smoke; subprocess kapanmamalı. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #212: Auth işlemi UID ve yaşam döngüsü

**Epic:** #206. **Dependencies:** Bağımsız; #58/#215 bunu tüketir.

**Files:** `src/auth/firebase_auth_native.*`, `src/auth/platform/platform_credentials_*`, `addons/firebase/auth/*`, `addons/firebase/core/firebase_result.gd`, `src/core/outcome.h`, `tests/test_auth_mock.gd`.

**Interfaces:** Kaynak User/UID + işlem nesli; ikinci UI isteğine ERR_BUSY=-6; sign-out bekleyen işlemi ERR_CANCELLED ile sonlandırır.

- [ ] **Step 1 — Regression/spec testi:** test_link_cannot_target_changed_uid, test_auth_ui_busy, test_late_auth_callback_after_shutdown: yanlış UID'ye link yok; task tek kez tamamlanır.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Ortak auth kontrolünü provider ediniminden önce kur; callback sadece geçerli işlem neslini tamamlasın.
- [ ] **Step 4 — Doğrulama:** Kontrollü gecikmeli testler; Apple/Game Center UI cihaz kanıtı #55. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #213: Auth mock oturum doğruluğu

**Epic:** #206. **Dependencies:** Bağımsız; #212/#58/#215 fixture'ları bunu tüketir.

**Files:** `addons/firebase/auth/firebase_auth_mock.gd`, `tests/test_auth_mock.gd`.

**Interfaces:** Native ERR_NO_USER ve kalıcı provider→UID eşlemesi; yalnız test yardımcılarıyla çoklu hesap/gecikme.

- [ ] **Step 1 — Regression/spec testi:** test_signed_out_token_and_delete_fail; test_provider_relogin_keeps_uid; test_link_keeps_anonymous_uid; test_credential_collision.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Mock hesap haritasını instance ömrüyle sınırla; gerçek disk oturumu simüle etme.
- [ ] **Step 4 — Doğrulama:** Auth mock suite; #69 yalnız yardımcıları explicit parity istisnası yapar. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #214: Döngüsel veri sınırı

**Epic:** #206. **Dependencies:** Bağımsız.

**Files:** `addons/firebase/functions/firebase_functions.gd`, `src/core/variant_convert.*`, `src/functions/firebase_functions_native.cpp`, `src/database/firebase_database_native.cpp`, `tests/test_functions_mock.gd`, `tests/test_database_mock.gd`.

**Interfaces:** ERR_INVALID_ARGUMENT; aktif recursion yolu ve en fazla 100 container, ürüne özgü daha dar limitler korunur.

- [ ] **Step 1 — Regression/spec testi:** test_cyclic_array_rejected, test_indirect_cycle_rejected, test_shared_subtree_allowed, test_depth_100_and_101; başarısız dönüşüm SDK çağırmaz.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** GDScript/native cycle ve derinlik kontrolünü ekle; native dönüşüm hatasını çağıranlara taşı.
- [ ] **Step 4 — Doğrulama:** Functions/Database suite + native giriş smoke; script overflow/çökme olmamalı. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #58: Google iOS ve Android

**Epic:** #206. **Dependencies:** #212/#213; ortak build/export değişiklikleri sıralanır.

**Files:** `addons/firebase/auth/*`, `src/auth/*`, `src/auth/platform/*`, `android/src/org/godotengine/godotfirebase/*`, `addons/firebase/export/*`, `tools/bootstrap.sh`, `tools/build_android_aar.sh`, `tests/test_auth_mock.gd`.

**Interfaces:** sign_in_with_google() -> FirebaseTask; link_with_google() -> FirebaseTask. Oyun OAuth ayarları spec A.

- [ ] **Step 1 — Regression/spec testi:** test_google_cancel_preserves_session, test_google_config_missing, test_google_link_keeps_uid; yeni ve önceden yetkilendirilmiş hesap seçimi.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Android Credential Manager ve iOS GoogleSignIn sadece credential edinir; mevcut C++ Auth giriş/link yoluna bağla. iOS URL callback/export'u tamamla.
- [ ] **Step 4 — Doğrulama:** Pinned dependency fixture build; #55/#59 ile iOS↔Android aynı Google hesabı UID kanıtı. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #215: Play Games SDK platform helper

**Epic:** #206. **Dependencies:** #212/#213; #60 oyun entegrasyonu olarak ayrı kalır.

**Files:** `addons/firebase/auth/*`, `src/auth/*`, `Android credential bridge`, `Android exporter/AAR`, `tests/test_auth_mock.gd`.

**Interfaces:** sign_in_with_play_games_platform()/link_with_play_games_platform() -> FirebaseTask; kod alan mevcut metotlar değişmez.

- [ ] **Step 1 — Regression/spec testi:** test_play_games_helper_disabled, test_play_games_cancel, test_play_games_external_code_unchanged, test_play_games_ios_unsupported.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** İsteğe bağlı PGS v2 helper app/server client ID ile taze auth code edinir; mevcut exchange yolunu kullanır.
- [ ] **Step 4 — Doğrulama:** #59 Android release/minification; helper ve dış kod API ayrı ayrı. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #65: Firestore mock sorguları

**Epic:** #207. **Dependencies:** #211 ile kuralları uyumlu tut; bağımsız mock düzeltmesi.

**Files:** `addons/firebase/firestore/firebase_firestore_mock.gd`, `tests/test_firestore_mock.gd`.

**Interfaces:** Mevcut query; iç içe alan çözümü ve eksik/null ayrımı.

- [ ] **Step 1 — Regression/spec testi:** test_nested_field_filter; test_order_excludes_missing_before_limit; test_multi_field_order.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Tek alan çözümleyicisini filtre/sıralamada kullan; eksik order alanlarını limit öncesi dışla.
- [ ] **Step 4 — Doğrulama:** Firestore mock suite. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #70: Timestamp sınır eşliği

**Epic:** #207. **Dependencies:** Bağımsız; #216'ya regression tabanı.

**Files:** `addons/firebase/firestore/firebase_value.gd`, `tests/test_firebase_value.gd`, `tests/test_firestore_mock.gd`.

**Interfaces:** seconds -62135596800..253402300799, nanos 0..999999999; int türleri.

- [ ] **Step 1 — Regression/spec testi:** test_timestamp_min_max_and_outside: belge ve filtrede sınır kabul, dışı ERR_INVALID_ARGUMENT.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** GDScript sınırlarını mevcut native doğrulamayla eşleştir.
- [ ] **Step 4 — Doğrulama:** FirebaseValue/Firestore suite. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #216: Firestore görünür senkronizasyon

**Epic:** #207. **Dependencies:** #211/#65/#70; #71 opsiyonel timeout işi bloklamaz.

**Files:** `addons/firebase/firestore/*`, `src/firestore/*`, `tests/test_firestore_mock.gd`, `yeni tests/test_firestore_sync_mock.gd`.

**Interfaces:** Spec B imzaları: source, query_snapshot, metadata listener, network ve wait_pending_writes; query Array sonucunu korur.

- [ ] **Step 1 — Regression/spec testi:** test_cache_source_and_miss; test_empty_query_metadata; test_metadata_only_listener_opt_in; test_pending_barrier_excludes_later_write; test_user_change_fails_barrier.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Snapshot metadata/source ve SDK network/barrier bağlarını ekle; mock local/server state'ini kontrollü ayır.
- [ ] **Step 4 — Doğrulama:** Mock suite; #55/#59 offline→kill→restart→reconnect ve ACK tek-tamamlama kanıtı. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #66: Database mock veri tabanı

**Epic:** #207. **Dependencies:** Bağımsız; #217/#218 testlerinin tabanı.

**Files:** `addons/firebase/database/firebase_database_mock.gd`, `tests/test_database_mock.gd`.

**Interfaces:** Kök scalar/array/dictionary/null; boş üst düğüm temizliği.

- [ ] **Step 1 — Regression/spec testi:** test_root_scalar_and_array; test_last_child_delete_prunes_parent; test_listener_root_value.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Mevcut kök store/snapshot semantiğini düzelt.
- [ ] **Step 4 — Doğrulama:** Database mock suite; gerçek persistence iddiası yok. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #217: Database başlangıç persistence

**Epic:** #207. **Dependencies:** #66; Core dokunuşunu #86 sahibiyle koordine et, #90'ı zorunlu bekleme.

**Files:** `addons/firebase/core/firebase.gd`, `addons/firebase/database/*`, `src/database/*`, `tests/test_database_mock.gd`, `yeni tests/test_database_config.gd`.

**Interfaces:** firebase/database/persistence_enabled=false; backend initialize(persistence_enabled=false)->Error; set_network_enabled(bool)->FirebaseTask.

- [ ] **Step 1 — Regression/spec testi:** test_persistence_before_first_reference; test_absent_setting_is_false; test_invalid_setting_unavailable; test_network_toggle_repeat.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Ayarı autoload'da okuyup ilk reference öncesi uygula; runtime setter ekleme.
- [ ] **Step 4 — Doğrulama:** Mock/config suite; #55/#59 true/false persistence karşılaştırmalı process-kill kanıtı. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #218: Database presence primitive'leri

**Epic:** #207. **Dependencies:** #66; ağ integration #217 ile. OnDisconnect persistence gerektirmez.

**Files:** `addons/firebase/database/*`, `src/database/*`, `tests/test_database_mock.gd`, `yeni tests/test_database_presence_mock.gd`, `yeni examples/database_presence.gd`.

**Interfaces:** Spec C dört OnDisconnect metodu + yalnız iki exact .info okuma yolu.

- [ ] **Step 1 — Regression/spec testi:** test_info_reads_allowed_writes_rejected; test_disconnect_registration_ack; test_cancel_prevents_action; test_reconnect_needs_registration; test_removed_listener_no_callback.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Okuma/yazma path doğrulamasını ayır; SDK DisconnectionHandler future'larını mevcut request sistemine bağla.
- [ ] **Step 4 — Doğrulama:** Mock suite + #55/#59 ani ağ kesilmesi. Örnek ACK sonra online ve bağlantı başına kayıt kullanır. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #69: Sekiz ürün API eşlik gate'i

**Epic:** #208. **Dependencies:** Mevcut beş üründe şimdi başlanır; her yeni modül kendi parity satırını ekler.

**Files:** `yeni tests/test_backend_contracts.gd`, `tests/firebase_test.gd yalnız subset-safe gereği varsa`, `native ClassDB stub kayıtları`.

**Interfaces:** Metot/default/type/sinyal eşliği; mock yardımcıları explicit istisna, unavailable stub skipped.

- [ ] **Step 1 — Regression/spec testi:** test_installed_module_contracts; test_missing_stub_is_skipped; test_remote_config_class_mapping.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Reflection karşılaştırmasını kur; kurulmamış modülleri preload ile zorunlu kılma.
- [ ] **Step 4 — Doğrulama:** Godot suite, mevcut stub ve subset fixture; gerçek Firebase davranışı kanıtı olarak sunma. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #219: Analytics modülü

**Epic:** #208. **Dependencies:** #69 test tabanı; Auth zorunlu değil.

**Files:** `yeni addons/firebase/analytics/*`, `yeni src/analytics/*`, `yeni tests/test_analytics_mock.gd`, `ürünün Core/build/bootstrap/export/AAR kayıtları`.

**Interfaces:** Spec D metotları; task success local SDK call; consent verilen anahtarları günceller.

- [ ] **Step 1 — Regression/spec testi:** test_event_validation_and_scalar_parameters; test_collection_disabled_semantics; test_consent_partial_update; test_user_id_clear; startup metadata fixture.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Pinned firebase_analytics bağla, API/mock/native ve export startup ayarlarını uygula; mevcut Android dependency etkisini kaydet.
- [ ] **Step 4 — Doğrulama:** Mock/parity/build; Android/iOS DebugView event/parametre kanıtı. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #220: Remote Config temel modülü

**Epic:** #208. **Dependencies:** #69; Auth/Analytics zorunlu değil.

**Files:** `yeni addons/firebase/remote_config/*`, `yeni src/remote_config/*`, `yeni tests/test_remote_config_mock.gd`, `Core native-name mapping ve ürün build/export kayıtları`.

**Interfaces:** Spec E ensure_initialized/defaults/settings/fetch/activate/get_value/get_info imzaları.

- [ ] **Step 1 — Regression/spec testi:** test_offline_defaults; test_fetch_does_not_activate; test_activate_changes_once; test_value_source_conversion; test_fetch_throttled; test_ms_conversion_bounds.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Pinned instance API ve defaults/fetched/active mock modeli; remote_config native-class mapping'i düzelt.
- [ ] **Step 4 — Doğrulama:** Mock/parity/build; mobil fetch→activate→restart/offline kanıtı. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #221: Remote Config realtime

**Epic:** #208. **Dependencies:** #220; #86 mevcut dispatch/lifetime sözleşmesi.

**Files:** `Remote Config API/mock/native`, `tests/test_remote_config_mock.gd`, `yeni examples/remote_config.gd`.

**Interfaces:** start_listening()->FirebaseTask; stop_listening()->void; config_updated/config_update_failed sinyalleri.

- [ ] **Step 1 — Regression/spec testi:** test_duplicate_start_single_listener; test_update_does_not_activate; test_stop_and_teardown_suppress_callback; test_reconnect_update.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** SDK listener handle'ını tek sahiplikle tut; sinyalleri Core dispatch'ten geçir.
- [ ] **Step 4 — Doğrulama:** Mock suite; mobil publish→updated_keys→explicit activate. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #222: Crashlytics ortak API ve Android

**Epic:** #208. **Dependencies:** #69; oyun config'i ve build-ID kaynakları export fixture'ında doğrulanır.

**Files:** `yeni addons/firebase/crashlytics/*`, `yeni src/crashlytics/firebase_crashlytics_native.*`, `yeni src/crashlytics/platform/crashlytics_android.cpp`, `Android Java bridge`, `yeni tests/test_crashlytics_mock.gd`, `export/Gradle/AAR kayıtları`.

**Interfaces:** Spec F metotları; stack {function,file,line}; collection/unsent task anlamları.

- [ ] **Step 1 — Regression/spec testi:** test_bad_stack_rejected; test_nonfatal_payload; test_collection_enabled_unsent_false; test_clear_user_id; clean-install startup-disabled fixture.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Java/NDK SDK ve uyumlu pinned Gradle plugin'ini bağla; Firebase App'i çoğaltma. iOS'u bu ara adımda unavailable tut.
- [ ] **Step 4 — Doğrulama:** Mock/parity; iki oyun generic prebuilt fixture, Android R8/minify ve nonfatal kanıtı. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #223: Crashlytics iOS ve semboller

**Epic:** #208. **Dependencies:** #222; #54/#55/#59 platform sahibiyle koordinasyon.

**Files:** `yeni src/crashlytics/platform/crashlytics_ios.mm`, `SConstruct/bootstrap/export/build`, `yeni tools/upload_crashlytics_symbols.sh`, `yeni examples/crashlytics_smoke/ fixture`.

**Interfaces:** Spec F aynı public API; semboller binary/build/ABI/UUID provenance ile eşleşir.

- [ ] **Step 1 — Regression/spec testi:** test_symbol_artifact_matches_binary fixture; iOS collection/unsent davranış parity; debug-only native crash fixture.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** iOS bridge/framework kaynaklarını ekle; Android unstripped/R8 ve iOS dSYM saklama/upload adımlarını tamamla.
- [ ] **Step 4 — Doğrulama:** Her mobil platformda native crash→restart→console'da bilinen fonksiyon adı; engine sembol kapsamını açık kaydet. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #224: Yeni ürün release kabulü

**Epic:** #208. **Dependencies:** #219–#223/#69; final composable release #90/#85/#86/#67/#68. Geliştirme API'leri bu final gate'i beklemez.

**Files:** `tools/package.sh`, `.github/workflows/build.yml`, `module kayıtları`, `yeni tests/test_sdk_capability_packages.py`, `README.md`, `AGENTS.md`, `yeni docs/verification/sdk-capabilities.md`.

**Interfaces:** Takip sürümü: sekiz ürün/full + sekiz tekil = dokuz ZIP; eski altı-paket kilometre taşı geriye dönük değişmez.

- [ ] **Step 1 — Regression/spec testi:** test_new_modules_full_union; test_selected_dependencies; test_no_game_config; test_symbol_provenance; ters/tekrar import/kaldırma ve eski kombinasyon regressionları.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** Ürün stage/export/CI seçimini ve belgeleri yeni release için genişlet; universal/split kararını yeniden verme.
- [ ] **Step 4 — Doğrulama:** Üç yeni tekil, telemetry-only, sekiz ürün full, Auth+Firestore/Auth+Database smoke; 255 native build yok. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

### Task #55 / 59: Mevcut mobil kabul kartlarını tamamla

**Epic:** #206. **Dependencies:** Özellik bazında fazlı: #212/#58/#215 ve #216–#218. Erken #90 kanıtını yeni ürünlere bağlama.

**Files:** `Mevcut mobil fixture'lar`, `docs/verification/sdk-capabilities.md ve modular-release.md ilgili kanıt bağlantıları`.

**Interfaces:** Kaydedilmiş kaynak commit/config/platform/komut/log; kimlik bilgilerini belgeye yazma.

- [ ] **Step 1 — Regression/spec testi:** Anonim→link UID; kill/relogin/ikinci cihaz; iOS↔Android Google UID; UI sırasında sign-out; offline process restart; disconnect register/cancel.
- [ ] **Step 2 — İlk kontrol:** İlgili Godot testini/yeni fixture'ı çalıştır; yeni davranışın mevcut kodda eksik/yanlış olduğunu doğrula. Zaten geçen davranış için yapay başarısızlık üretme.
- [ ] **Step 3 — Uygulama:** #55/#59'a eklenen checklist'leri gerçek cihazda yürüt; native eksik davranışı ilgili ürün kartına geri bağla.
- [ ] **Step 4 — Doğrulama:** Cihaz/console/config yoksa açık kalır. Analytics/RC/Crash kanıtını #219–#223 sahiplenir. İlgili ortak kontrolleri çalıştır ve gerçek çıktı/kanıt yolunu karta ekle.
- [ ] **Step 5 — Review ve teslim:** Diff'i görev kapsamına göre incelet; yalnız bu değişikliğin dosyalarını commit et, kabul maddelerini gerçek kanıtla güncelle.

## Kapsam kararları ve takip

- #71 timeout uygulanacaksa waiter-local olur; alttaki task pending ve geç SDK sonucu geçerli kalır. #216 bunu beklemez.
- #60 Play Games oyun butonu/Console ayar kartıdır; #215 SDK provider köprüsüdür. Mükerrer sayılıp birbirine dönüştürülmez.
- Apple Android OAuth mevcut iOS Apple API'sinin ayrı gelecekteki uzantısıdır; ortak cihazlar arası provider bu dalgada Google'dır.
- SDK örnekleri query/presence/config kullanımını gösterir; oyuncu cüzdanı, mağaza, para transferi veya otomatik veri birleştirme yazmaz.
- Yeni modüllerin dokuz-ZIP hedefi #224 uygulanınca ilgili üretim README/AGENTS sayıları güncellenir; eski plan tarihçesi geriye dönük başarıya çevrilmez.

## Plan self-review

- [x] Kullanıcının SDK sınırı ile oyun backend'i ayrıldı; ekonomi terimi açıklığa kavuşturuldu.
- [x] Sorgu/auth bulguları, istenen sağlayıcılar, Firestore/RTDB ve üç yeni ürünün her biri kartla eşleşiyor.
- [x] Public API imzaları spec ile kartlarda aynı; query Array dönüşü ve Play Games(code) korunuyor.
- [x] Remote Config underscore adı, ilk-start collection, offline ACK, listener ömrü ve Crashlytics sembolleri görev kabulünde yer alıyor.
- [x] Var olan #58/#65/#66/#69/#70 tekrar açılmadı; #55/#59 cihaz sahipliği ve #71 koşullu backlog durumu korundu.
- [x] #90/#67/#68 bağımlılıklarına yeni çevrim eklenmedi; doing kartlar ve native topoloji kararı değiştirilmedi.
- [x] Üretim kodu, test sonucu veya cihaz çalışması planlama sırasında tamamlanmış gibi işaretlenmedi.

