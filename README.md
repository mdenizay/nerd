# Nerd

Laravel Herd'e alternatif, menü çubuğundan yönetilen native (SwiftUI) bir macOS yerel PHP geliştirme ortamı.

## Özellikler

- **Menü çubuğu paneli** — web sunucusu aç/kapa, siteler (tarayıcı / editör / Finder / Terminal / `npm run dev`), servis anahtarları, varsayılan PHP & Node seçimi.
- **Siteler** — park klasörlerindeki (varsayılan `~/Sites`) her klasör otomatik olarak `klasör.test` olur; başka klasörler "bağlanabilir". Site başına PHP sürümü, Node sürümü ve HTTPS.
- **Çoklu PHP** — Homebrew ile 7.4–8.5 kurulum/kaldırma, her sürüm için ayrı PHP-FPM havuzu, php.ini, modül listesi, `pecl install`.
- **Çoklu Node** — nodejs.org'dan indirilen sürümler (`~/.nerd/node`) + Homebrew Node'ları; varsayılan sürüm `~/.nerd/bin` üzerinden.
- **Hızlı proje oluşturma** — Blade, Livewire, Inertia + React / Vue / Svelte resmi starter kit'leri, boş PHP veya herhangi bir composer paketi; SQLite / MySQL / PostgreSQL ayarı, veritabanı oluşturma, migrate, `npm install && build`, git init.
- **Servisler** — MySQL, MariaDB, PostgreSQL 17/18, Redis, Valkey, Memcached, Mailpit, Meilisearch, MinIO (`brew services`).
- **Veritabanı görüntüleyici** — site `.env` dosyalarından otomatik bağlantılar + elle eklenenler; tablo gezinme, sıralama, sayfalama, hücre düzenleme (çift tık), NULL, satır silme, SQL konsolu.
- **Görevler** — tüm kurulum/komut çıktıları canlı log olarak.

## Mimari

| Parça | Nasıl |
|---|---|
| Web sunucusu | Caddy (`~/.nerd/Caddyfile`), macOS'ta 80/443 portları root gerektirmez |
| PHP | Sürüm başına `php-fpm` (unix socket `~/.nerd/run/phpXY.sock`) |
| DNS | Uygulama içi küçük UDP DNS sunucusu (127.0.0.1:53535) + `/etc/resolver/test` (tek seferlik yönetici izni). `.localhost` seçilirse hiç gerekmez |
| HTTPS | Caddy `tls internal`; kök sertifika Ayarlar'dan sisteme eklenir |
| Yapılandırma | `~/.nerd/config.json`, loglar `~/.nerd/logs` |

## Derleme

Gereksinimler: macOS 15+, Xcode / Swift 6, Homebrew.

```bash
./scripts/build-app.sh          # build/Nerd.app (release)
open build/Nerd.app
```

Geliştirme için: `open build/Nerd.app --args --window --page=sites` pencereyi belirli bir sayfada açar.

İlk açılışta Genel Bakış ekranındaki uyarılar üzerinden Caddy kurulumu, `.test` DNS çözümleyicisi ve `~/.nerd/bin`'in PATH'e eklenmesi tek tıkla yapılabilir.
