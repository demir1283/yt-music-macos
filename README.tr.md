<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="YT Music uygulama simgesi">
</p>

<h1 align="center">YT Music for macOS</h1>

<p align="center">
  Mac için SwiftUI ile yazılmış yerel bir YouTube Music istemcisi.
</p>

<p align="center">
  <img alt="Sürüm 3.0.0-dev" src="https://img.shields.io/badge/s%C3%BCr%C3%BCm-3.0.0--dev-ff2d55">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white">
  <img alt="MIT Lisansı" src="https://img.shields.io/badge/lisans-MIT-3c8dbc">
</p>

<p align="center">
  <a href="README.md">English</a> · <b>Türkçe</b>
</p>

<p align="center">
  <img src="docs/screenshots/home.png" alt="Ana sayfa">
</p>

> **Resmî değildir.** YouTube veya Google ile bağlantısı yoktur. “YouTube” ve “YouTube Music”, Google LLC'nin ticari markalarıdır. Kendi YouTube Music hesabınız gerekir; en iyi ses kalitesi için Premium gerekir.

## Neler ekliyor

YouTube Music'in sunduklarına ek olarak uygulamanın kendine ait birkaç özelliği var:

- **Ana sayfa:** kısayollar, sanatçı istasyonları, hızlı seçimler ve dinlediklerine göre değişen satırlar.
- **Yeni çıkanlar:** takip ettiğin ve dinlediğin sanatçıların son yayınları.
- **Bildirimler:** takip ettiğin müzik kanallarının son yüklemeleri, Shorts olmadan.
- **Radyo düzenleme (isteğe bağlı):** resmî şarkı sürümlerini öne alır, her şarkıyı bir kez çalar; DJ setlerine dokunmaz.
- **Mac'inde dinleme geçmişi:** yukarıdaki öneriler için kullanılır; kapatabilir veya silebilirsin.
- **Uzun setler:** dinlediğin türlerde, normal YouTube'dan DJ setleri ve canlı kayıtlar.
- **Ses çıkışı:** yalnızca bu uygulama için hoparlör, Bluetooth, USB veya ekran çıkışı seç; ya da AirPlay kullan.

## Yenilikler

- **3.0 (hazırlanıyor):** şarkılar arasında eşit ses, uyku zamanlayıcı, dinleme özetin ve geri alınabilen beğenilmeyen içerik.
- **2.7 — Uygulama içinden güncelleme:** yeni sürüm kenar çubuğunda görünür; tek tıkla indirilip derlenir. Bkz. [Güncelleme](#güncelleme).
- **2.6 — İngilizce arayüz:** uygulamanın tamamı Mac'inin diline (Türkçe veya İngilizce) ya da Ayarlar'da seçtiğine uyar.
- **2.5 — Yeni “Yeni çıkanlar” sayfası:** takip ettiğin ve dinlediğin sanatçıların son yayınları; ortak yüklemelerde her kanal bir bağlantı.

Tam liste [değişiklik günlüğünde](CHANGELOG.md).

## Kurulum

Uygulamayı kendin derlersin. Yaklaşık bir dakika sürer, Xcode gerekmez:

```bash
xcode-select --install          # bir kez, Command Line Tools kurulu değilse
git clone https://github.com/demir1283/yt-music-macos.git
cd yt-music-macos
./build.sh --install            # uygulamayı derler ve /Applications'a kopyalar
```

Sonra kenar çubuğunda **Giriş yap**'a tıklayıp Google ile giriş yap. macOS 14 veya üstü gerekir.

### Güncelleme

Uygulama açılışta ve günde bir kez GitHub'da yeni sürüm olup olmadığına bakar. Yeni sürüm çıktığında kenar çubuğunda görünür: **Güncelle**, uygulamayı derlediğin klasörde `git pull` ve `./build.sh` çalıştırır, ardından yeni sürüm açılır. Denetimi **Ayarlar → Güncelleme**'den kapatabilirsin.

Elle güncellemek için proje klasöründe: `git pull && ./build.sh --install`. Her sürümde e-posta almak için bu sayfada **Watch → Custom → Releases**'ı seç.

**2.6 veya öncesinden geliyorsan:** bir kez elle güncelle; 2.7'den sonra uygulama kendisi yapar.

## Neden yerel bir uygulama

- **İçinde tarayıcı yok.** SwiftUI arayüzü ve Apple'ın kendi ses oynatıcısı. Electron yok, web oynatıcı yok.
- **Tam kalite.** Premium ile 256 kbps AAC, olduğu gibi çalınır.
- **Hafif.** Arka planda çalarken yaklaşık %1,5 CPU ve ~170 MB bellek (geliştiricinin MacBook'unda ölçüldü).
- **macOS'a uyumlu.** macOS 26'da Liquid Glass, medya tuşları, Denetim Merkezi, Dock menüsü, açık ve koyu mod.

## Klavye kısayolları

| Kısayol | İşlem |
|---|---|
| Boşluk | Çal / duraklat |
| ⌥⌘→ / ⌥⌘← | Sonraki / önceki şarkı |
| ⌘↑ / ⌘↓ | Sesi aç / kıs |
| ⌥⌘L | Beğen |
| ⌘F | Ara (öneri seçmek için ↑↓, kapatmak için Esc) |
| ⌘1 … ⌘4 | Ana sayfa, Keşfet, Kitaplık, Beğenilen müzikler |
| ⌘[ | Geri |
| ⇧⌘L | Şarkı sözleri |
| ⌘, | Ayarlar |

## Gizlilik

- **Parolan uygulamaya hiç ulaşmaz.** Google'ın kendi sayfasında giriş yaparsın; uygulama yalnızca oturum çerezlerini Mac'inde tutar. **Çıkış yap** onları siler.
- **Sunucu, analiz veya izleme yok.** Uygulama yalnızca YouTube / Google, [LRCLIB](https://lrclib.net) (şarkı sözleri) ve GitHub (yeni sürüm var mı diye; Ayarlar'dan kapatılabilir) ile konuşur.
- **Dinleme geçmişin Mac'inde kalır** (en fazla 4 MB). Ayarlar'dan kapatabilir veya silebilirsin.
- **Bu depoda anahtar veya token yok.** Her şey çalışırken senin oturumundan okunur.

<details>
<summary><b>Nasıl çalışır</b></summary>

```
Google girişi ─▶ oturum çerezleri ─▶ URLSession
                                       │
YouTube Music + YouTube verisi ◀── JavaScriptCore'da bridge.js
                                       │
Dinleme geçmişi ─▶ ListeningProfile ─▶ ana sayfa · radyo temizliği · yeni çıkanlar
                                       │
Akış adresi ──▶ yt-dlp-ejs (YouTube'un akış sınamasını çözer)
                                       │
          DashToHLS (ses dosyasının kendi dizininden bir çalma listesi)
                                       │
                 AVPlayer ──▶ seçilen çıkış veya AirPlay
```

`Tools/bridge.js` dosyasını düzenlersen Swift kopyasını `./build.sh` (ya da `Tools/gen-bridge.sh`) yazar. Testler: `swift test` (Xcode gerekir) ve `node --test "Tools/tests/*.test.mjs"`; GitHub Actions her push'ta ikisini de çalıştırır.
</details>

<details>
<summary><b>Sorun giderme</b></summary>

- **Sayfalar boş kalıyor:** Görünüm menüsünden **Yeniden bağlan**'ı kullan. YouTube bir onay sayfası gösteriyorsa YouTube Music'i bir kez tarayıcıda aç (⇧⌘Y).
- **Tanı kaydı:** `defaults write io.github.demir1283.ytmusic diagnosticLog -bool true` uygulamanın yanına `YT Music.log` yazar; `defaults delete io.github.demir1283.ytmusic diagnosticLog` kapatır. Paylaşmadan önce kaydı oku.
- **1.0'dan yükseltme:** bir kez daha giriş yap; ayarlar sıfırdan başlar.
</details>

## Geri bildirim

- **Hata mı buldun, bir özellik mi istiyorsun?** [Issue aç](https://github.com/demir1283/yt-music-macos/issues/new/choose); her biri için kısa bir form var.
- **Sorun veya fikrin mi var?** [Tartışmalar](https://github.com/demir1283/yt-music-macos/discussions) bölümünü kullan.
- **Güvenlik sorunu mu?** Herkese açık issue yerine [Güvenlik sekmesinden](https://github.com/demir1283/yt-music-macos/security/advisories/new) özel olarak bildir.

Türkçe de İngilizce de olur. Hesap adını, çerezleri veya token'ları asla paylaşma.

## Teşekkürler

- [yt-dlp-ejs](https://github.com/yt-dlp/ejs) (kamu malı), [meriyah](https://github.com/meriyah/meriyah) (ISC) ve [astring](https://github.com/davidbonnet/astring) (MIT) ile.
- Eşzamanlı şarkı sözleri için [LRCLIB](https://lrclib.net).
- Tasarım Apple Music, Spotify ve [Kaset](https://github.com/sozercan/kaset)'ten esinlendi.

## Lisans

[MIT](LICENSE). Pakete dahil yt-dlp-ejs kendi lisansını korur (`Resources/ejs/LICENSE`).
