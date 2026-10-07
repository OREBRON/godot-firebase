# AdMob ödüllü reklam SSV şablonu

Ödüllü reklam izleyen oyuncunun enerjisini sunucu verir. Google ödülü, reklam
biriminin sunucu tarafı doğrulama (SSV) URL'ine imzalı bir GET isteğiyle
bildirir. Bu Cloud Function imzayı doğrular, ödülü izinli listeyle karşılaştırır
ve `users/{uid}.energy` alanını her `transaction_id` için bir kez artırır.

Şablon eklenti ZIP'ine girmez. Ekonomi oyuna aittir; oyun bu klasörü kopyalayıp
uyarlar. İstemci akışı ve editör simülatörü
[`examples/rewarded_energy.gd`](../../examples/rewarded_energy.gd) içindedir.

## Dosyalar

- `functions/index.js`: 2. nesil HTTPS fonksiyonu `admobRewardCallback`,
  `REGION` ve `CONFIG`.
- `functions/src/verify.js`: imzalanan kısmı ayırır, Google anahtarlarını indirir
  ve ECDSA P-256/SHA-256 imzasını doğrular.
- `functions/src/grant.js`: izinli liste, idempotent transaction, üst sınır ve günlük limit.
- `functions/src/callback.js`: doğrulama ve ödül sonucunu HTTP koduna çevirir.
- `firestore.rules`, `firebase.json`: kurallar, dağıtım ve emulator ayarı.

## Akış

1. Oyun `request_consent()`, `load_rewarded(unit)` ve ardından
   `show_rewarded(ad, {"user_id": uid, "custom_data": "energy"})` çağırır.
2. Google şu isteği gönderir:
   `GET <url>?ad_network=…&ad_unit=…&custom_data=…&reward_amount=…&reward_item=…&timestamp=…&transaction_id=…&user_id=…&signature=…&key_id=…`
3. Fonksiyon şunları yapar:
   - `signature` ve `key_id` her zaman son iki parametredir.
   - İmzalanan mesaj, ham sorgunun `&signature=` öncesidir. Decode, yeniden
     encode ya da sıralama yapılmaz.
   - Anahtar `key_id` ile `verifier-keys.json` içinden seçilir. Liste en fazla
     24 saat önbelleklenir; bilinmeyen `key_id` en çok dakikada bir yeniden indirir.
   - `ad_unit`, `reward_item` ve `custom_data` izinli listede olmalıdır.
     `user_id` geçerli bir Firestore belge kimliği olmalıdır.
   - Tek transaction'da `ad_rewards/{transaction_id}` kaydı varsa durur. Yoksa
     enerjiyi artırır ve kaydı yazar.
4. Oyun enerjiyi `listen_doc("users/<uid>")` ile görür. `rewarded: true` yalnız
   "ödül işleniyor" göstergesidir; SSV gecikebilir.

| Durum | Yanıt |
|---|---|
| Enerji verildi; aynı `transaction_id` tekrar geldi (`duplicate`); `daily_limit`; `energy_full`; izinli listede değil | 200 |
| Bozuk sorgu: imza/`key_id` yok ya da sonda değil, parametre tekrarı, eksik `transaction_id`/`reward_amount` | 400 |
| İmza tutmuyor ya da `key_id` bilinmiyor | 403 |
| Anahtar indirme veya Firestore hatası | 500 |

Google 200 dışındaki yanıtta isteği 1 sn arayla en fazla 5 kez tekrarlar.
500 sonrası tekrar, `ad_rewards` kaydı sayesinde ikinci kez enerji vermez.

## Yapılandırma

`functions/index.js`:

- `REGION`: Firestore konumuna yakın bölge.
- `CONFIG.adUnits`: anahtar reklam birimi kimliğidir (`ca-app-pub-…/NNNNNNNNNN`).
  Callback yalnız `/` sonrasını gönderir; iki biçim de eşleşir. Değer:
  - `rewardItem`: AdMob'da birime girilen ödül öğesi (büyük/küçük harf duyarlı),
  - `customData`: oyunun `show_rewarded` ile gönderdiği `custom_data`,
  - `maxAmount`: bir reklamın vereceği en fazla enerji; `reward_amount` daha büyükse kırpılır.
- `CONFIG.energyCap`: enerji üst sınırı. Enerji doluysa kayıt `energy_full` olur.
- `CONFIG.dailyLimit`: oyuncu başına UTC gününde enerji veren reklam sayısı;
  `0` sınırsızdır. Aşan istek `daily_limit` olarak kaydedilir ve 200 alır.
- `ADMOB_SSV_KEYS=test`: Google test anahtarlarını (`verifier-keys-test.json`)
  seçer. Yalnız geliştirme projesinin `functions/.env.<proje-id>` dosyasına yaz;
  production'da tanımlama.

Sunucu alanları (`energy`, `ad_reward_day`, `ad_reward_count`) ve `ad_rewards`
koleksiyonu `src/grant.js` ile `firestore.rules` içinde birlikte değişir.

## Dağıtım

1. Klasörü oyunun Firebase projesine kopyala. Projede `firebase.json` varsa
   `functions` girdisini (codebase `admob-ssv`) ekle ve kuralları kendi
   `firestore.rules` dosyana birleştir.
2. `REGION` ve `CONFIG` değerlerini düzenle.
3. `cd functions && npm install && npm test`
4. `firebase deploy --only functions:admob-ssv,firestore:rules --project <proje-id>`
   (Cloud Functions Blaze plan ister).
5. Deploy çıktısındaki `Function URL` adresini al.

AdMob'da SSV URL'i her ödüllü reklam birimi için ayrı girilir: Apps → uygulama →
Ad units → birim → Advanced settings → Server-side verification → Callback URL.
Doğrulama aracının isteği izinli listeye uymazsa fonksiyon enerji vermeden 200
döner; sebep fonksiyon log'undadır.

## Test reklamları

- Geliştirmede gerçek reklam gösterme. Google'ın örnek birimleri
  (`test_rewarded_ad_unit()`) senin SSV URL'ine bağlı değildir. SSV'yi denemek
  için kendi birimini `set_request_configuration({"test_device_ids": [...]})`
  ile kayıtlı test cihazında kullan.
- Geliştirme projesinde `ADMOB_SSV_KEYS=test` kullan. Test callback'inin hangi
  anahtar listesiyle imzalandığı cihaz kabulünde kesinleşir. Yanlış liste 403
  ve log'da `unknown key_id` olarak görünür.

## İstemci neden enerji vermez

`show_rewarded` sonucu cihazda üretilir. Değiştirilmiş bir istemci reklam
izlemeden aynı sonucu ve Firestore yazısını üretebilir. Google imzası yalnız
sunucuda doğrulanır. Bu yüzden enerjiyi yalnız fonksiyon yazar; kurallar
istemcinin `energy`, sayaç alanları ve `ad_rewards` yazmasını reddeder.
`user_id` istemciden gelir; yalnız izlenen reklamın ödülünün kime yazılacağını seçer.

## Firestore kuralları

- `users/{uid}`: yalnız sahibi okur. Sahibi oyun alanlarını yazar ama sunucu
  alanlarını oluşturamaz, değiştiremez veya silemez. Belgeyi silmek enerjiyi
  ve günlük sayacı sıfırlayacağı için kapalıdır; hesap temizliği Admin SDK ile yapılır.
- Diğer oyun alanlarını daraltmak için kuraldaki `hasOnly` örneğini kullan.
- `users/{uid}/…` alt koleksiyonları, `templates/firestore.rules` gibi sahibine açıktır.
- `ad_rewards/**` istemciye kapalıdır. Admin SDK kuralları atlar.

## Editör simülatörü

Editörde ve masaüstünde SSV callback'i gelmez. `examples/rewarded_energy.gd`,
`Firebase.is_mock("admob")` ve `Firebase.is_mock("firestore")` doğruyken
`ad_event` `reward_earned` olayında Firestore mock'una fonksiyonun yazacağı
artışı yazar (`FirebaseValue.increment`, en çok `reward_per_ad`, `energy_cap`'e
kadar). İmza, izinli liste, idempotens ve günlük limit simüle edilmez; onlar
`npm test` içindedir. Simülatör oyunun debug kodudur; mobilde mock olmadığından
gerçek veriye yazmaz.

## Testler

- `cd functions && npm test`: paket kurmadan Node 22 ile çalışır, ağa çıkmaz.
  Testler kendi ürettikleri P-256 anahtarını ve bellek içi transaction'ı kullanır.
- `npm run test:rules`: `firestore.rules` kurallarını Firestore Emulator'da
  dener. Firebase CLI ve Java gerekir.
- Gerçek Google callback'i ve cihazda tek seferlik enerji artışı cihaz kabulünde
  doğrulanır; yerel testler onun yerine geçmez.
