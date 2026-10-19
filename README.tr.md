# Nerd

[English](README.md) · **Türkçe**

Menü çubuğundan yönetilen, SwiftUI ile yazılmış, Laravel Herd'e açık kaynak bir alternatif.

## Özellikler

- **Menü çubuğu paneli** — web sunucusu, siteler (tarayıcı / editör / Terminal / dev sunucusu), servis anahtarları, varsayılan PHP & Node.
- **Siteler** — park klasörlerindeki (varsayılan `~/Sites`) her klasör otomatik `klasör.test` olur; başka klasörler bağlanabilir. Laravel, düz PHP, **Next.js** ve **Astro** projeleri otomatik tanınır. Site başına PHP / Node sürümü ve HTTPS.
- **Proje sihirbazı** — Blade, Livewire, Inertia + React / Vue / Svelte starter kit'leri, Next.js, Astro, boş PHP veya herhangi bir composer paketi; veritabanı, migrate, frontend derlemesi ve git dahil.
- **Çoklu PHP** — Homebrew ile 7.4–8.5, sürüm başına PHP-FPM, php.ini, modüller, `pecl install`.
- **Çoklu Node** — nodejs.org sürümleri + Homebrew Node'ları.
- **Mail** — dahili SMTP yakalayıcı (`127.0.0.1:2525`): HTML / metin / kaynak görünümü, ekler. Yeni Laravel projeleri otomatik yönlendirilir.
- **Servisler** — MySQL, MariaDB, PostgreSQL, Redis, Valkey, Memcached, Mailpit, Meilisearch, MinIO (`brew services`).
- **Veritabanı** — SQLite / MySQL / PostgreSQL görüntüleyici: sıralama, sayfalama, hücre düzenleme, SQL konsolu.
- **Görünüm ve dil** — sistem teması, açık veya koyu; İngilizce ve Türkçe.
- **Otomatik güncelleme** — yeni sürümler GitHub'dan indirilir, imzası doğrulanır ve yeniden başlatınca kurulur.

## Dağıtım: Dokploy ve Forge

- **Dokploy:** Sitenin "Dağıtım" bölümünden (ya da sihirbazda "Docker dosyaları ekle") production için `Dockerfile`, `docker-compose.yml` ve `.dockerignore` üretilir:
  - **Laravel:** [serversideup/php](https://serversideup.net/open-source/docker-php/) (nginx + php-fpm) imajı kullanılır. Migration'lar açılışta otomatik çalışır. `queue` ve `scheduler` servisleri de eklenir. `.env`'deki ayara göre MySQL, PostgreSQL ya da SQLite kullanılır; SQLite kalıcı `storage` volume'unda tutulur. Gerekiyorsa Redis eklenir.
  - **Next.js:** `output: "standalone"` ile derlenir.
  - **Astro:** statik site nginx ile, SSR (`@astrojs/node`) Node ile sunulur.

  Dokploy'da "Compose" türünde bir uygulama oluşturup repoyu bağlayın ve `app` servisine domain ekleyin. Gizli değerleri (`APP_KEY`, `DB_PASSWORD`) Environment sekmesine girin.
- **Laravel Forge:** Ek dosya gerekmez; repoyu bağlayıp deploy edin.

Komut satırından:

```bash
/Applications/Nerd.app/Contents/MacOS/Nerd docker ~/Sites/my-app
```

## Mimari

| Parça | Nasıl |
|---|---|
| Web sunucusu | Caddy (`~/.nerd/Caddyfile`); macOS'ta 80/443 portları root gerektirmez |
| PHP | Sürüm başına `php-fpm` (unix socket) |
| Next.js / Astro | Site başına sabit portta `npm run dev`, Caddy ile reverse proxy |
| DNS | Uygulama içi UDP DNS (127.0.0.1:53535) + `/etc/resolver/test` (tek seferlik yönetici izni). `.localhost` seçilirse gerekmez |
| Mail | Uygulama içi SMTP sunucusu, mesajlar `~/.nerd/mail/*.eml` |
| HTTPS | Caddy `tls internal`; kök sertifika Ayarlar'dan sisteme eklenir |
| Yapılandırma | `~/.nerd/config.json`, loglar `~/.nerd/logs` |

## Kurulum

macOS 15 veya üstü (Apple silicon ya da Intel) ve [Homebrew](https://brew.sh) gerekir:

```bash
brew install --cask mdenizay/tap/nerd
```

Uygulama imzalı ve notarize edilmiştir. Caddy, bağımlılık olarak birlikte kurulur.

### Kaynaktan derleme

Xcode / Swift 6 gerekir.

```bash
git clone https://github.com/mdenizay/nerd.git
cd nerd
./scripts/build-app.sh
open build/Nerd.app
```

İlk açılışta Genel Bakış ekranından Caddy kurulumu, `.test` DNS çözümleyicisi ve `~/.nerd/bin`'in PATH'e eklenmesi tek tıkla yapılır.

Laravel projelerinde e-postaları Nerd'e göndermek için:

```dotenv
MAIL_MAILER=smtp
MAIL_HOST=127.0.0.1
MAIL_PORT=2525
```

Geliştirme: `open build/Nerd.app --args --window --page=sites` pencereyi belirli bir sayfada açar.

## Lisans

[MIT](LICENSE)
