# AdMob ödüllü reklam SSV şablonu

Ödüllü reklam izleyen oyuncuya enerji, can, altın ya da başka bir ödülü sunucu
verir. Google ödülü, reklam biriminin sunucu tarafı doğrulama (SSV) URL'ine
imzalı bir GET isteğiyle bildirir. Bu Cloud Function imzayı doğrular, oyunun
seçtiği ödülü izinli listeyle karşılaştırır ve `wallets/{uid}` belgesindeki
bakiyeyi her `transaction_id` için bir kez artırır. Bakiyeyi harcamak için
`spendReward` callable fonksiyonu vardır.

Şablon eklenti ZIP'ine girmez. Ekonomi oyuna aittir; oyun bu klasörü kopyalayıp
uyarlar. İstemci akışı ve editör simülatörü
[`examples/rewarded_ads.gd`](../../examples/rewarded_ads.gd) içindedir.

## Dosyalar

- `functions/index.js`:
  - SSV callback'i (`admobRewardCallback`),
  - harcama fonksiyonu (`spendReward`),
  - `REGION` ve `CONFIG`.
- `functions/src/verify.js`: imzalanan kısmı ayırır, Google anahtarlarını indirir
  ve ECDSA P-256/SHA-256 imzasını doğrular.
- `functions/src/grant.js`: yapılandırma kontrolü, ödül seçimi, idempotent
  transaction, üst sınır ve günlük limit.
- `functions/src/spend.js`: bakiyeyi sıfırın altına düşürmeden atomik harcama.
- `functions/src/callback.js`: doğrulama ve ödül sonucunu HTTP koduna çevirir.
- `firestore.rules`, `firebase.json`: kurallar, dağıtım ve emulator ayarı.

## Veri

| Yol | İçerik | Yazan |
|---|---|---|
| `wallets/{uid}` | `{energy: 12, lives: 3, coins: 150, …}` | Yalnız fonksiyonlar |
| `wallets/{uid}/ad_days/{YYYY-MM-DD}` | Gün içinde ödül veren reklam sayısı, ödül başına | Yalnız callback |
| `ad_rewards/{transaction_id}` | Her callback'in kaydı (ödül, miktar, durum) | Yalnız callback |
| `users/{uid}/…` | Oyunun kendi verisi | Oyuncu |

Yeni bir ödül eklemek için `CONFIG`'e eklemek yeterlidir; kurallar değişmez.

## Akış

1. Oyun her açılışta `request_consent()`, ardından `load_rewarded(unit)` çağırır.
2. Oyuncu hangi ödül için izleyeceğini seçer, oyun reklamı gösterir:
   `show_rewarded(ad, {"user_id": uid, "custom_data": "lives"})`.
   `custom_data` ödülün adıdır.
3. Google şu isteği gönderir:
   `GET <url>?ad_network=…&ad_unit=…&custom_data=…&reward_amount=…&reward_item=…&timestamp=…&transaction_id=…&user_id=…&signature=…&key_id=…`
4. Fonksiyon şunları yapar:
   - **İmza:** `signature` ve `key_id` her zaman son iki parametredir. İmzalanan
     mesaj, ham sorgunun `&signature=` öncesidir; decode, yeniden encode ya da
     sıralama yapılmaz.
   - **Anahtar:** `key_id` ile `verifier-keys.json` içinden seçilir. Liste en
     fazla 24 saat önbelleklenir; bilinmeyen `key_id` listeyi en çok dakikada bir
     yeniden indirir.
   - **İzin:** `ad_unit` izinli olmalı ve `custom_data` o birimin izin verdiği bir
     ödül olmalıdır. `user_id` geçerli bir Firestore belge kimliği olmalıdır.
   - **Miktar:** `CONFIG`'den gelir. AdMob'daki birim ödül ayarı
     (`reward_item`/`reward_amount`) yalnız kayda yazılır.
   - **Tek sefer:** Tek transaction'da `ad_rewards/{transaction_id}` kaydı varsa
     durur; yoksa bakiyeyi artırır ve kaydı yazar.
5. Oyun bakiyeleri `listen_doc("wallets/<uid>")` ile görür. `rewarded: true`
   yalnız "ödül işleniyor" göstergesidir; SSV gecikebilir.

| Durum | Yanıt |
|---|---|
| Ödül verildi; aynı `transaction_id` tekrar geldi (`duplicate`); `daily_limit`; `cap_reached`; izinli listede değil | 200 |
| Bozuk sorgu: imza/`key_id` yok ya da sonda değil, parametre tekrarı, eksik `transaction_id`/`reward_amount` | 400 |
| İmza tutmuyor ya da `key_id` bilinmiyor | 403 |
| Anahtar indirme veya Firestore hatası | 500 |

Google 200 dışındaki yanıtta isteği 1 sn arayla en fazla 5 kez tekrarlar.
500 sonrası tekrar, `ad_rewards` kaydı sayesinde ikinci kez ödül vermez.

## Harcama

İstemci `wallets/{uid}`'e yazamaz; can veya enerji harcamak için fonksiyonu çağırır:

```gdscript
var spent: FirebaseResult = await Firebase.functions.call_function("spendReward", {"reward": "lives", "amount": 1}).wait()
if spent.ok:
	print("kalan can: ", spent.value.balance)
elif spent.error_code == 9: # FAILED_PRECONDITION: bakiye yetmiyor
	show_out_of_lives()
```

- Oturum açmamış istek `unauthenticated`, bilinmeyen ödül veya geçersiz miktar
  (`1..1000000` dışında) `invalid-argument` alır.
- Bakiye yetmezse hiçbir şey yazılmaz ve `failed-precondition` döner.
- Oynanıştan kazanılan altın gibi başka kazançları da sunucu yazmalıdır (ör. seviye
  sonu doğrulayan ayrı bir fonksiyon); bu şablonun kapsamı dışındadır.

## Yapılandırma

`functions/index.js`:

- `REGION`: Firestore konumuna yakın bölge.
- `CONFIG.rewards`: ödül adı → `{amount, cap, dailyLimit}`.
  - **Ad:** düz bir Firestore alan adıdır (`^[a-z][a-z0-9_]*$`) ve oyunun
    gönderdiği `custom_data` ile aynıdır.
  - **`amount`:** bir reklamın verdiği miktardır.
  - **`cap`:** reklamla ulaşılabilecek en yüksek bakiyedir (`0` = sınırsız);
    doluysa kayıt `cap_reached` olur.
  - **`dailyLimit`:** bu ödülü veren reklam sayısının oyuncu başına UTC günlük
    sınırıdır (`0` = sınırsız); aşan istek `daily_limit` olarak kaydedilir.
- `CONFIG.adUnits`: reklam birimi → izin verdiği ödül adları.
  - **Anahtar:** reklam birimi kimliğidir (`ca-app-pub-…/NNNNNNNNNN`). Callback
    yalnız `/` sonrasını gönderir; iki biçim de eşleşir.
  - **Kullanım:** bir birim birden çok ödül verebilir; ödüle göre ayrı birim de
    kullanılabilir.
- `checkConfig`, hatalı yapılandırmada fonksiyonun yüklenmesini durdurur (deploy
  sırasında görünür).
- `ADMOB_SSV_KEYS=test`: Google test anahtarlarını (`verifier-keys-test.json`)
  seçer. Yalnız geliştirme projesinin `functions/.env.<proje-id>` dosyasına yaz;
  production'da tanımlama.

## Dağıtım

1. Klasörü oyunun Firebase projesine kopyala. Projede `firebase.json` varsa
   `functions` girdisini (codebase `admob-ssv`) ekle ve kuralları kendi
   `firestore.rules` dosyana birleştir.
2. `REGION` ve `CONFIG` değerlerini düzenle.
3. `cd functions && npm install && npm test`
4. `firebase deploy --only functions:admob-ssv,firestore:rules --project <proje-id>`
   (Cloud Functions Blaze plan ister).
5. Deploy çıktısındaki `admobRewardCallback` URL'ini al.

AdMob'da SSV URL'i her ödüllü reklam birimi için ayrı girilir: Apps → uygulama →
Ad units → birim → Advanced settings → Server-side verification → Callback URL.
Doğrulama aracının isteği izinli listeye uymazsa fonksiyon ödül vermeden 200
döner; sebep fonksiyon log'undadır.

## Test reklamları

- Geliştirmede gerçek reklam gösterme. Google'ın örnek birimleri
  (`test_rewarded_ad_unit()`) senin SSV URL'ine bağlı değildir. SSV'yi denemek
  için kendi birimini `set_request_configuration({"test_device_ids": [...]})`
  ile kayıtlı test cihazında kullan.
- Geliştirme projesinde `ADMOB_SSV_KEYS=test` kullan. Test callback'inin hangi
  anahtar listesiyle imzalandığı cihaz kabulünde kesinleşir. Yanlış liste 403
  ve log'da `unknown key_id` olarak görünür.

## İstemci neden ödül vermez

`show_rewarded` sonucu cihazda üretilir. Değiştirilmiş bir istemci reklam
izlemeden aynı sonucu ve Firestore yazısını üretebilir. Google imzası yalnız
sunucuda doğrulanır. Bu yüzden bakiyeleri yalnız fonksiyonlar yazar; kurallar
istemcinin `wallets` ve `ad_rewards` yazmasını reddeder. `user_id` ve
`custom_data` istemciden gelir ama Google tarafından imzalanır. İstemci yalnız,
izlenen reklamın ödülünün kime ve izinli ödüllerden hangisine yazılacağını seçer.
Miktar, üst sınır ve günlük limit sunucudadır.

## Firestore kuralları

- `wallets/{uid}/…`: yalnız sahibi okur; hiçbir istemci yazamaz. Admin SDK
  kuralları atlar.
- `users/{uid}/…`: belge ve alt koleksiyonlar sahibine açıktır
  (`templates/firestore.rules` gibi). Oyun şemasına göre daralt.
- `ad_rewards/**`: istemciye kapalıdır.

## Editör simülatörü

Editörde ve masaüstünde SSV callback'i gelmez. `examples/rewarded_ads.gd`,
`Firebase.is_mock("admob")` ve `Firebase.is_mock("firestore")` doğruyken iki
şeyi taklit eder:

- `ad_event` `reward_earned` olayında fonksiyonun yazacağı artışı Firestore
  mock'undaki `wallets/<uid>` belgesine yazar (`reward_amounts`/`reward_caps`).
- Harcamayı `spendReward` yerine aynı mock belgeye yazar.

İmza, izinli liste, idempotens ve günlük limit simüle edilmez; onlar `npm test`
içindedir. Simülatör oyunun debug kodudur; mobilde mock olmadığından gerçek
veriye yazmaz.

## Testler

- `cd functions && npm test`: paket kurmadan Node 22 ile çalışır, ağa çıkmaz.
  Testler kendi ürettikleri P-256 anahtarını ve bellek içi transaction'ı kullanır.
- `npm run test:rules`: `firestore.rules` kurallarını Firestore Emulator'da
  dener. Firebase CLI ve Java gerekir.
- Gerçek Google callback'i ve cihazda tek seferlik ödül cihaz kabulünde
  doğrulanır; yerel testler onun yerine geçmez.
