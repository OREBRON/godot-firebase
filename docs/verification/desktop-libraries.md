# Desktop editör kütüphaneleri

Tarih: 2026-10-03. Hedef engine: `tools/versions.env` içindeki Godot 4.7.2.

## Kabul koşulları

1. Windows/Linux x86_64 ve macOS arm64/x86_64 editöründe GDExtension yüklenir.
   Descriptor yalnız açık desktop mimari etiketlerini kullanır; generic macOS
   eşlemesi bir Intel editöre arm64 dosyası seçtiremez.
2. Boş uzantı native Firebase sınıflarını kaydetmez. Kurulu sekiz ürünün
   GDScript API'leri otomatik mock backend ile başlar; anonim Auth isteği
   bu API üzerinden tamamlanır.
3. Kaynak, derleme talimatları ve dört hazır binary aynı commit kapsamındadır.
   Binary'ler Git LFS ile tutulur; kullanıcı `git lfs pull` sonrasında desktop
   editörünü derleyici veya Firebase SDK kurmadan açabilir.
4. Linux, Windows ve iki Mac mimarisinde aynı Godot sürümüyle editör importu,
   mock başlangıcı ve stok testleri CI'da kontrol edilir. LFS binary'leri
   yeniden derlenmeden önce test edilir; sonra source rebuild ayrıca doğrulanır.
5. Bozuk/eksik uzantı, import/script hatası veya timeout kontrolü başarısız
   yapar. Godot'un import hatasında sıfır exit code döndürmesi başarı sayılmaz.

İlk istekteki boş uzantı/mock yaklaşımı korunur. Bu kabul, desktop'ta gerçek
Firebase SDK/network desteği veya mobil cihaz kabulü anlamına gelmez.

## Uygulama ve derleme

- `src/desktop/godot_firebase_stub.c`: yalnız GDExtension initialization ABI'si,
  scene seviyesinde boş init/shutdown callback'leri ve exported entry symbol.
- `tools/build_desktop_stub.py`: desktop C derlemesi; SDK/bindings indirmez.
  Aynı stub debug/release editör ve desktop çalıştırmalarında kullanılır.
- `tools/build.sh`: macOS'ta her iki mimari; seçildiğinde Windows/Linux x86_64.
  Mobile SCons/SDK akışı korunur; desktop kaynak modül seçimine bağımlı değildir.
- `.github/workflows/desktop.yml`: Ubuntu 24.04 x86_64, Windows 2025 x86_64,
  macOS 15 arm64 ve macOS 15 Intel. Godot resmi release ZIP'i yayımlanan
  SHA-512 ile doğrulanır. Checkout `lfs: true` kullanır.
- `tools/run_tests.py`: platformlar arasında ortak test çalıştırıcısı.
  `tools/run_tests.sh` ve `make test` aynı çalıştırıcıya gider.

Derleme komutları ve kullanıcı kurulumu [README](../../README.md#desktop-editöründe-geliştirme)
içindedir. Godot platform/mimari seçimi
[resmi descriptor rehberine](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html#libraries-section)
dayanır; runner mimarileri
[GitHub runner referansında](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
tanımlıdır.

Hazır Mac dosyaları Apple Clang 21.0.0 / Xcode toolchain ile minimum macOS
11.0 hedefleyerek üretildi. Windows/Linux dosyaları macOS arm64 host üzerinde
Zig 0.15.2 ile cross-build edildi. İndirilen Zig arşivi resmi SHA-256
`3cc2bab367e185cdfb27501c4b30b1b0653c28d9f73df8dc91488e66ece5fa6b`
ile kontrol edildi; toolchain depoya eklenmez.

| Descriptor etiketi | Bayt | SHA-256 |
|---|---:|---|
| `windows.x86_64` | 3072 | `b5c92c309e982c34e116b3f508ed3d1b88d59c1400d8699b012dd6e04661f0a5` |
| `linux.x86_64` | 2456 | `78f5e6e707bb670b2661b087affaa17ae25d5288f0f273a818fd9588f019849d` |
| `macos.arm64` | 16832 | `76215fa1f120d63e442eb6ffbbd4e7eaa813715551f7c63535dcddf639ef8df0` |
| `macos.x86_64` | 4232 | `f620f2e3bfe5e533a64f688ddef7bf0c4095bc3018265b8a370311005c84c66f` |

## Yerel kanıt

- TDD RED: `test_desktop_extension.gd`, eski descriptor'da dört açık mimari
  eşlemesi olmadığı ve generic Mac eşlemeleri bulunduğu için başarısız oldu.
- TDD RED: bozuk kütüphane fixture'ında eski `run_tests.sh` sıfır döndü;
  `test_test_runner.py` bu yanlış başarıyı yakaladı.
- GREEN: import hataları artık başarısız sayılır; regression testi geçti.
  Hata kontrolü geçici kaldırıldığında test tekrar başarısız oldu; mutation
  geri alındı.
- Mac arm64: `GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/run_tests.sh`
  ile editör importu ve **26 GDScript testinin tamamı** geçti.
- Mac x86_64: aynı universal Godot executable, `arch -x86_64` / Rosetta ile
  çalıştırıldı; Intel stub yüklüyken editör importu ve **26 test** geçti.
  Bu, fiziksel Intel Mac üzerinde kabul yerine geçmez.
- Temiz desktop kurulum: geçici proje dizininde `.godot` önbelleği,
  mobil binary veya SDK olmadan dört hazır stub ile import ve 26 test geçti.
- CI'ın Godot indirme/SHA-512/version kontrolü macOS üzerinde aynı workflow
  koduyla çalıştırıldı ve resmi 4.7.2 executable'ı doğruladı. YAML ve gömülü
  Python sözdizimi kontrol edildi; bu, GitHub job sonucu olarak sayılmaz.
- Python stok testleri: `python3 -m unittest discover -s tests -p 'test_*.py'`
  ile 10 test, 0 başarısızlık; bir Android NDK symbol fixture'ı ilgili ortam
  değişkenleri olmadığı için mevcut davranışıyla skipped.
- `file` dört binary'nin hedef mimari/formatını doğruladı. Windows PE export
  tablosunda entry symbol bulundu ve import directory boştu. Mac binary'leri
  yalnız sistem `libSystem` bağımlılığı taşıyor; Linux ELF'in `DT_NEEDED`
  listesi boş. Initialization ABI/callback ve
  null output kontrolleri yerel yükleme ile doğrulandı.

Native Auth lifecycle ve native signature parity desktop'ta mevcut testlerin
belirttiği gibi skipped; mock başarısı native Firebase kabulü olarak yazılmaz.
Negatif girdileri sınayan bazı stok testler beklenen `ERROR` mesajları üretir;
test base'in başarısızlık listesi, script hataları ve tamamlanma/exit durumu
esas alınır. Editör importundaki `ERROR` mesajları ise her zaman başarısızdır.

## Bekleyen kanıt

GitHub workflow henüz çalıştırılmadı. Windows/Linux runtime yüklemesi ve fiziksel
Intel Mac import/test kanıtı CI job'ları tamamlanınca ayrıca kaydedilmelidir.
Yerel format/cross-build kanıtı bu runtime sonuçlarının yerine geçmez.
