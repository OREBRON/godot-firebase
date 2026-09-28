# Godot Firebase

Godot 4.7.2 için modüler Firebase eklentisi. iOS'ta Firebase C++ SDK 13.13.0
(Firebase iOS SDK 12.19) üzerinde çalışır. Oyun yalnızca ihtiyaç duyduğu
modülleri alır:

| Modül | Klasör | Native sınıf | İçerik |
|---|---|---|---|
| core (zorunlu) | `core/` | `FirebaseAppNative` | App başlatma, görev ve sonuç tipleri |
| auth | `auth/` | `FirebaseAuthNative` | Anonim, Game Center, Sign in with Apple, hesap bağlama, silme |
| firestore | `firestore/` | `FirebaseFirestoreNative` | Doküman okuma/yazma, sorgu, batch, dinleyici |

Durum: GDScript API ve mock testleri geçiyor. Native kod henüz Firebase SDK
ile derlenmedi ve cihazda denenmedi (bkz. [Doğrulanmamış noktalar](#doğrulanmamış-noktalar)).

## Oyuna ekleme

1. `tools/bootstrap.sh`, ardından modül seçerek derle:
   ```bash
   tools/build.sh --modules auth
   tools/build.sh --modules auth,firestore
   ```
2. `addons/godot_firebase/` klasörünü oyuna kopyala. Kullanmadığın modülün
   klasörünü (`auth/` veya `firestore/`) sil. Native derleme ve klasörler
   aynı modül listesine sahip olmalı; seçilen liste `bin/modules.txt` içinde.
3. Proje ayarlarında eklentiyi aç. `Firebase` autoload'u eklenir.
4. Firebase konsolundan `GoogleService-Info.plist` indir, `res://` köküne koy
   (dosya adı birebir aynı kalmalı). iOS export ayarlarında:
   - `firebase/sign_in_with_apple` açıksa `entitlements/additional` içine
     `<key>com.apple.developer.applesignin</key><array><string>Default</string></array>`
   - `firebase/sign_in_with_game_center` açıksa `entitlements/game_center`
   - Minimum iOS 15.
5. `templates/firestore.rules` kurallarını Firebase projesine yükle.

## Kullanım

```gdscript
var result: FirebaseResult = await Firebase.auth.sign_in_anonymously().wait()
if not result.ok:
	push_warning(result.error_message)
	return
var uid: String = result.value.uid

# Anonim ilerlemeyi kalıcı hesaba bağla; uid değişmez.
await Firebase.auth.link_with_apple().wait()

var path := "users/%s/saves/main" % uid
await Firebase.firestore.set_doc(path, {"level": 3, "updated_at": FirebaseValue.server_timestamp()}, true).wait()
var snapshot: Dictionary = (await Firebase.firestore.get_doc(path).wait()).value
if snapshot.exists:
	print(snapshot.data.level)

var top: FirebaseResult = await Firebase.firestore.query("scores", [["score", ">=", 100]], [["score", "desc"]], 10).wait()
var id: int = Firebase.firestore.listen_doc(path, func(r: FirebaseResult): print(r.value.data))
Firebase.firestore.remove_listener(id)
```

- Her istek `FirebaseTask` döner; `await task.wait()` bir `FirebaseResult`
  verir: `ok`, `value`, `error_code`, `error_message`. Negatif kodlar
  eklentiden gelir (`FirebaseResult.ERR_*`), pozitifler Firebase'den.
- Özel değerler: `FirebaseValue.timestamp()`, `server_timestamp()`,
  `increment()`, `delete_field()`. Zaman damgaları okunurken
  `{__firebase__ = "timestamp", seconds, nanos}` sözlüğü olarak gelir.
- Desteklenen tipler: null, bool, int, float, String, PackedByteArray, Array
  (iç içe dizi yok), Dictionary (String anahtarlı). Geçersiz veri native
  katmana ulaşmadan `ERR_INVALID_ARGUMENT` ile döner.
- Silinen modülün özelliği `null` olur (`Firebase.firestore == null`). Bu yüzden
  `Firebase.auth` ve `Firebase.firestore` tipsizdir; sonuçları tipli değişkene
  ata (`var r: FirebaseResult = await ...`) ya da `var auth: FirebaseAuth = Firebase.auth`.
- Editörde ve masaüstünde native yapılandırma yoksa bellek içi mock çalışır
  (`Firebase.is_mock("auth")`). Mobilde native başlatılamazsa mock'a düşülmez;
  istekler `ERR_UNAVAILABLE` döner.
- Hesap açtıran oyunlar App Store kuralı gereği hesap silme sunmalıdır:
  `Firebase.auth.delete_account()`.

## Geliştirme

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/run_tests.sh
```

`tests/test_native_convert.gd` masaüstü native derlemesi varken C++ değer
dönüştürücüsünü sınar, yoksa atlanır. Masaüstünde gerçek Firebase için
`res://google-services-desktop.json` (ya da `firebase/desktop_config_path`
ayarı) kullanılır; Firebase C++ masaüstü desteği beta ve yalnızca geliştirme
içindir.

### CI (self-hosted runner)

`.github/workflows/build.yml` `[self-hosted, macOS, ARM64]` runner'da çalışır
(Xcode, `godot` 4.7.2 ve `uv` gerekir). SDK indirmeleri runner'da
`../godot-firebase-third-party` altında kalıcı tutulur; ilk çalışma ~2.2 GB
indirir. Her çalışma mock testlerini koşar, `auth` ve `auth,firestore`
varyantlarını macOS + iOS için derler, native testleri tekrar koşar ve
`godot_firebase-auth.zip`, `godot_firebase-auth-firestore.zip` paketlerini
artifact olarak yükler. Paket oyunun kök dizinine açılır.

Bağımlılık sürümleri `tools/versions.env` içindedir. godot-cpp'nin 4.7 tag'i
olmadığı için `master` bir commit'e sabitlenir ve `api_version=4.7` ile derlenir.

## Doğrulanmamış noktalar

İlk native derleme ve cihaz denemesinde kontrol edilecekler:

- `SConstruct` içindeki Firebase SDK dizin ve framework adları (zip yapısına göre).
- Swift çalışma zamanı bağlama bayrakları (FirebaseAuth ve Firestore Swift içerir).
- Godot iOS export'unun dinamik xcframework'ü gömmesi ve `*.bundle`
  kaynaklarını `add_apple_embedded_platform_bundle_file` ile kopyalaması.
- Uygulama boyutuna etkisi (özellikle Firestore).
- Android: henüz yok. Aynı C++ modülleri, JNI köprüsü ve Gradle bağımlılıkları
  ile eklenecek.
