<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="YT Music uygulama simgesi">
</p>

<h1 align="center">YT Music for macOS</h1>

<p align="center">
  Mac için yerel bir YouTube Music istemcisi: ana sayfası, araması ve radyosu<br>
  YouTube Music'in kendisinden daha akıllı.
</p>

<p align="center">
  <img alt="Sürüm 2.5.0" src="https://img.shields.io/badge/s%C3%BCr%C3%BCm-2.5.0-ff2d55">
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

## YouTube Music'te olmayıp burada olanlar

| | YouTube Music | YT Music for macOS |
|---|---|---|
| **Yeni çıkanlar** | Genel bir sayfa | Takip ettiğin sanatçıların son 20 yayını ve dinlediğin sanatçıların yeni müzikleri |
| **Bildirimler** | Zil, çoğu Shorts | Takip ettiğin müzik kanallarının son yüklemeleri, Shorts yok |
| **Radyo** | Şarkı sürümleri, klipler ve tekrar yüklemeler karışık | Önce resmî şarkı sürümleri, her şarkı bir kez, DJ setleri olduğu gibi |
| **Seni tanıması** | Sunucuda, görünmez | Mac'inde tutulan, okuyup silebileceğin bir dinleme profili |
| **DJ setleri** | Nadiren çıkar | Dinlediğin türlerde, normal YouTube'dan “Uzun setler” |
| **Ses çıkışı** | Yalnızca sistem çıkışı | Yalnızca bu uygulama için hoparlör, Bluetooth, USB veya ekran seç; ya da AirPlay |
| **Uzun kayıtlar** | Başlaması uzun sürebilir | Saatlik setler bir saniyede başlar, anında sarılır |

## 2.5'te yenilikler

- **Yeni “Yeni çıkanlar” sayfası:** takip ettiğin sanatçıların son 20 yayını, dinlediğin sanatçıların yeni müzikleri, senin için seçilenler, YouTube Music'teki yenilikler ve yeni müzik videoları. Ana sayfadaki satır da aynı yayınları gösterir.
- **Ortak yüklemeler:** her kanalın adı kendi sayfasına giden bir bağlantıdır.
- Ayrıca arama önerileri, daha net bir arama sayfası ve birçok küçük düzeltme; tam liste [değişiklik günlüğünde](CHANGELOG.md).

## Kurulum

Uygulamayı kendin derlersin. Yaklaşık bir dakika sürer, Xcode gerekmez:

```bash
xcode-select --install          # bir kez, Command Line Tools kurulu değilse
git clone https://github.com/demir1283/yt-music-macos.git
cd yt-music-macos
./build.sh --install            # uygulamayı derler ve /Applications'a kopyalar
```

Sonra kenar çubuğunda **Giriş yap**'a tıklayıp Google ile giriş yap. macOS 14 veya üstü gerekir.

## Neden yerel bir uygulama

- **İçinde tarayıcı yok.** SwiftUI arayüzü ve Apple'ın kendi ses oynatıcısı. Electron yok, web oynatıcı yok.
- **Tam kalite.** Premium ile 256 kbps AAC, olduğu gibi çalınır.
- **Hafif.** Arka planda çalarken yaklaşık %1,5 CPU ve ~170 MB bellek.
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
- **Sunucu, analiz veya izleme yok.** Uygulama yalnızca YouTube / Google ve [LRCLIB](https://lrclib.net) (şarkı sözleri) ile konuşur.
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

`Tools/bridge.js` dosyasını düzenlersen `Sources/YTMusicMac/Engine/BridgeScript.swift` içine de kopyala.
</details>

<details>
<summary><b>Sorun giderme</b></summary>

- **Sayfalar boş kalıyor:** Görünüm menüsünden **Yeniden bağlan**'ı kullan. YouTube bir onay sayfası gösteriyorsa YouTube Music'i bir kez tarayıcıda aç (⇧⌘Y).
- **Tanı kaydı:** `defaults write io.github.demir1283.ytmusic diagnosticLog -bool true` uygulamanın yanına `YT Music.log` yazar; `defaults delete io.github.demir1283.ytmusic diagnosticLog` kapatır. Paylaşmadan önce kaydı oku.
- **1.0'dan yükseltme:** bir kez daha giriş yap; ayarlar sıfırdan başlar.
</details>

## Teşekkürler

- [yt-dlp-ejs](https://github.com/yt-dlp/ejs) (kamu malı), [meriyah](https://github.com/meriyah/meriyah) (ISC) ve [astring](https://github.com/davidbonnet/astring) (MIT) ile.
- Eşzamanlı şarkı sözleri için [LRCLIB](https://lrclib.net).
- Tasarım Apple Music, Spotify ve [Kaset](https://github.com/sozercan/kaset)'ten esinlendi.

## Lisans

[MIT](LICENSE). Pakete dahil yt-dlp-ejs kendi lisansını korur (`Resources/ejs/LICENSE`).
