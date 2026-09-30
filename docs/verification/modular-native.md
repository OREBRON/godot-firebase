# Modüler native topoloji kanıtı (#83, #84)

Tarih: 2026-09-30. Geçici prototipler `build/probes/modular-native/` altındadır; üretim kodu değildir ve
depoya girmez. Boyut verisi: [modular-size.md](modular-size.md).

Adaylar spec'teki gibidir: **A** universal tek native, **B** her modüle ayrı `.gdextension`, **C** tek Core
GDExtension + özel loader.

## Ortam kısıtı

- Android cihaz bağlı değil, AVD yok. Emulator imajı disk dolduğu için indirilemedi.
- iPhone çevrimdışı; Xcode'da iOS simulator runtime kurulu değil. Diskte ~1-2 GB boş alan var.
- Bu yüzden Android APK cold-start, `App::Create` ve Firebase isteği **çalıştırılmadı**. Aşağıdaki "geçti"
  ifadeleri link, ELF ve host (macOS) Godot çalışma zamanı kanıtıdır; cihaz kanıtı değildir.

## Android (#83)

### B: ayrı `.gdextension` prototipi

Kaynak: `build/probes/modular-native/android/b/` (`build.sh`, `core_entry.cpp`, `auth_entry.cpp`,
`firestore_entry.cpp`, `core.map`, `module.map`). NDK 28.2.13676358, `aarch64-linux-android24`.

- **Core** (`libgodot_firebase_core.so`): eklentinin gerçek `src/core/firebase_app_native.cpp` dosyası, kendi
  godot-cpp kopyası ve `libfirebase_app.a`. Modüllere küçük bir C API verir
  (`godot_firebase_core_app()`, `godot_firebase_core_build_id()`).
- **Auth/Firestore** (`libgodot_firebase_{auth,firestore}.so`): kendi godot-cpp kopyası, kendi Firebase
  arşivi; `firebase_app` sembollerini `-lgodot_firebase_core` ile Core'dan alır. Core'daki Godot sınıfından
  miras almaz, App'i C API ile alır.

Link komutu (özet, tamamı `build.sh`):

```sh
clang++ --target=aarch64-linux-android24 -shared -fvisibility=hidden -Wl,--no-undefined \
  -o libgodot_firebase_core.so core_entry.o firebase_app_native.o libgodot-cpp...a \
  -Wl,--whole-archive libfirebase_app.a -Wl,--no-whole-archive -llog -Wl,--version-script=core.map
clang++ ... -o libgodot_firebase_auth.so auth_entry.o libgodot-cpp...a libfirebase_auth.a \
  -L. -lgodot_firebase_core -llog -Wl,--version-script=module.map
```

Core version script:

```
{
  global:
    extern "C++" { firebase::*; vtable?for?firebase::*; typeinfo?for?firebase::*; typeinfo?name?for?firebase::*; };
    godot_firebase_core_*;
    Java_*;
  local: *;
};
```

Modül version script yalnız `godot_firebase_*_init` giriş sembolünü export eder. lld'de tırnaklı
`"vtable for firebase::*"` desen değil tam ad sayılır ve link hatası verir; `?` joker karakteri gerekir.

Sonuçlar (`llvm-readelf -d`, `llvm-nm -D`):

| Binary | Stripped boyut | NEEDED | Export | godot:: export |
| --- | ---: | --- | ---: | ---: |
| core (whole-archive) | 1,191,112 | liblog, libc++_shared, libm, libdl, libc | 962 | 0 |
| core (dar `-u` listesi) | 1,082,048 | aynı | — | 0 |
| auth | 602,656 | **libgodot_firebase_core**, liblog, libc++_shared, libm, libdl, libc | 1 | 0 |
| firestore | 897,736 | **libgodot_firebase_core**, ... | 1 | 0 |

- `--no-undefined` ile üç binary de link oldu. Auth Core'dan 67, Firestore 60 sembol import eder
  (66/59 `firebase_app` sembolü + `godot_firebase_core_app`).
- **Tek sahip:** Unstripped modüllerde `firebase::util`, `app_common`, `AppCallback`, `CleanupNotifier`,
  `FutureManager` tanımı yok. Core ile ortak tanımlı semboller godot-cpp'nin gizli kopyası (2,245) ve birkaç
  inline/şablon Firebase fonksiyonudur (`FutureBase::operator=`, `ReferenceCountedFutureImpl` kurucusu);
  bunlar durum taşımaz.
- **godot-cpp izolasyonu:** Hiçbir binary `godot::` sembolü export etmez. Her modül ~330 KB'lık kendi
  godot-cpp kopyasını taşır.
- **STL:** Hepsi `libc++_shared.so` ister. Godot motoru (`libgodot_android.so`) da `libc++_shared.so` ister;
  APK'da tek kopya vardır ve Godot 4.7.2 şablonununkidir (clang 21). Eklenti NDK 28.2 (clang 19) ile derlenir;
  daha yeni libc++ ile çalışma ileri uyumludur, ama cihazda denenmedi.
- **Allocate/free, exception, RTTI:** `_Znwm`, `_ZdlPv`, `__cxa_throw`, `__gxx_personality_v0` ve
  `__class_type_info` vtable'ı her DSO'da undefined'dır, `libc++_shared`'dan çözülür; yerel `operator new`
  yok. Firebase tip bilgileri (`typeinfo for firebase::*`) Core'dan export edilir. Firestore arşivi STL stream
  typeinfo'larını weak data olarak da tanımlar; modülde yerelleştirildikleri için sınır ötesi `dynamic_cast`
  riski teoriktir ve cihazda sınanmadı.
- **Whole-archive:** Dar `-Wl,-u,<sembol>` listesi (Auth+Firestore importlarının birleşimi, 86 sembol)
  whole-archive'a göre 109,064 B küçük Core verdi ve iki modül de buna karşı link oldu. Liste bütün
  modüllerin importlarının birleşimi olmalıdır; aksi hâlde sonraki modül link olmaz. Dahil etme (whole-archive
  veya `-u`) ile görünürlük (version script) ayrı kararlardır.
- **JNI:** `firebase_app` yalnız `Java_com_google_firebase_app_internal_cpp_Log_nativeLog` export eder; modül
  arşivlerinde `Java_*` veya `JNI_OnLoad` yok, native kayıt `RegisterNatives` ile yapılır. `Java_*` adıyla
  çözüm için Core'un `System.loadLibrary` ile yüklenmesi yeterlidir (mevcut `FirebaseBridge` bunu yapar).

### B: Godot çalışma zamanı (host)

Kaynak: `build/probes/modular-native/host-b/`. Aynı düzen macOS arm64'te Firebase'siz kuruldu: Core dylib
saf C++ bir registry tutar; modül dylib'leri static initializer'da (Firebase `AppCallback` kaydı gibi)
kendilerini kaydeder, istekleri Core'a iletir. Godot 4.7.2 headless çıktı:

```
PROBE class FirebaseCoreProbe exists=true
PROBE class FirebaseAuthProbe exists=true
PROBE class FirebaseFirestoreProbe exists=true
PROBE mismatched build class exists=false
PROBE missing library class exists=false
PROBE registered before app create=["Auth", "Firestore", "Storage"]
PROBE modules at app create=3
PROBE core requests=3 (expected 3)
PROBE result=pass
```

Bulgular:

- Godot extension'ları alfabetik sırayla yükledi (auth, core, ...). Auth dylib'i dinamik bağımlılık olarak
  Core'u önce yükletti; Godot Core'u yüklerken aynı imajı kullandı. Registry tek kopya kaldı.
- Bütün modül static initializer'ları, GDScript'ten çağrılan App yaratımından önce çalıştı. Firebase App
  autoload `_enter_tree` içinde yaratıldığı için bu sıra B'de korunur.
- **Static initializer'lar hiçbir godot-cpp binding'i başlamadan çalışır.** Registry Godot tipi
  (`PackedStringArray`) kullanınca Godot çöktü (`godot::PackedStringArray::PackedStringArray()` içinde
  SIGSEGV). Firebase `AppCallback` saf C++ olduğu için sorun değildir; Core'un bu aşamada çağrılan her API'si
  Godot'dan bağımsız olmalıdır.
- **Eksik library** (`.gdextension` var, dylib yok): Godot "Can't open dynamic library ... no such file"
  hatası verir, sınıf yoktur.
- **Build ID uyuşmazlığı:** Modül init'i `godot_firebase_core_build_id()` farklıysa `false` döndürür; Godot
  "initialization function ... returned an error" hatası verir, sınıf yoktur. Ancak modülün static
  initializer'ı bu kontrolden **önce** çalıştı ve Core registry'sine kaydoldu (`Storage`). Gerçek Firebase'de
  bu, eski bir modülün `AppCallback`'inin `App::Create` sırasında çağrılması demektir. Core, App yaratmadan
  önce yüklü modüllerin build ID'sini kendisi doğrulamalıdır (#85/#86).
- GDScript tarafında "kurulu değil" (modül klasörü yok, API `null`) ile "kurulu ama native yok" (klasör var,
  sınıf yok, mobilde `ERR_UNAVAILABLE`) zaten ayrıdır; ayrıntılı neden Godot logundadır.

### C: tek Core + özel loader

Prototiplenmedi. Plan C'yi "B başarısız veya daha pahalıysa" ister; B link, ELF ve host çalışma zamanı
kontrollerinden geçti. C'nin ek bedeli statik olarak görünür:

- Modüller Core'un godot-cpp binding'ini kullanmalıdır. Mevcut godot-cpp arşivi `-fvisibility=hidden` ile
  derlenir; C için godot-cpp'nin görünür sembollerle ayrı derlenmesi ve Core'dan binlerce sembolün export
  edilmesi gerekir (Auth prototip objesi tek başına 67 `godot::` sembolü ister, geçişli binding runtime'ı
  daha fazlasını).
- Modül `.so` dosyaları `.gdextension` tanımı olmadığı için Godot export'u onları APK'ya koymaz; Core
  descriptor'ının `[dependencies]` bölümü veya ayrı export eklentisi gerekir. B'de Godot her modülü kendi
  descriptor'ı ile paketler.

### FirebaseInitProvider ve yükleme sırası

#89 sonrası APK'da `google_app_id` kaynağı yoktur. `FirebaseInitProvider` manifestte kalır ama kaynaksız
default App oluşturmaz (Firebase davranışı). Default App, bütün extension'lar yüklendikten sonra autoload'dan
`App::Create(options, env, activity)` ile oluşur. B'de modüller Godot extension yüklemesiyle, yani App'ten
önce yüklenir. Cihazda doğrulanmadı.

### Android değerlendirmesi

| Kurulum | A universal | B split | Fark |
| --- | ---: | ---: | ---: |
| Yalnız Auth | 2,934,296 (full `.so`) | 1,793,768 (core + auth) | B −1,140,528 |
| Auth + Firestore | 2,934,296 | 2,691,504 (core + auth + firestore) | B −242,792 |
| Beş modül | 2,934,296 | tahmin > A (her modül ~330 KB godot-cpp tekrarı) | B dezavantajlı |

Karşılaştırma için mevcut monolitik Auth-only `.so` 1,528,912 B'tır; B'nin Auth-only kurulumu bundan
264,856 B büyüktür. B'nin en iyi durumdaki tasarrufu ~1.1 MB'tır (APK'nın ~%1.3'ü); Maven seçimi ise
7,989,069 B fark yaratır ve native topolojiden bağımsızdır (#56).

B'nin Android bedeli: Core export listesi, modül başına godot-cpp tekrarı, build ID'nin Core'da ayrıca
doğrulanması, static-init kısıtı ve cihazda sınanmamış `libc++_shared`/RTTI sınırı.

**Sonuç (#90 girdisi):** B Android'de teknik olarak link olur ve Godot tarafında çalışır; ama tasarrufu
küçüktür ve beş modülde tersine döner. Android için A (universal) önerilir; tek koşul full native + seçili
Maven'in cihazda yüklendiğinin kanıtlanmasıdır (#56 a2, #59).

## iOS (#84)

Bu bölüm #84 ile doldurulur.

## Yeniden üretme

```sh
bash build/probes/modular-native/android/b/build.sh
bash build/probes/modular-native/host-b/build.sh
cd build/probes/modular-native/host-b/project && godot --headless --editor --quit && godot --headless --script res://probe.gd
```
