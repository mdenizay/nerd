# Nerd

**English** · [Türkçe](README.tr.md)

A native macOS local development environment for PHP, Laravel, Next.js, Astro and .NET, run from the menu bar. An open-source alternative to Laravel Herd, written in SwiftUI.

![Nerd](https://mdenizay.com/open-source/nerd/main.webp)

## Install

macOS 15 or later, on Apple silicon or Intel, with [Homebrew](https://brew.sh):

```bash
brew install --cask mdenizay/tap/nerd
```

The app is signed and notarized, Caddy is installed with it, and it keeps itself up to date from GitHub releases. On first launch, the Overview screen sets up the `.test` DNS resolver (asks for your password once) and adds `~/.nerd/bin` to your PATH.

## Features

- **Menu bar panel:** web server, sites (browser, editor, Terminal, dev server), service switches, default PHP and Node.
- **Sites:** every folder in your parked folders (default `~/Sites`) becomes `folder.test`; other folders can be linked. Laravel, plain PHP, **Next.js**, **Astro** and **ASP.NET** projects are detected automatically. PHP version, Node version and HTTPS per site.
- **Project wizard:** Laravel with the Blade, Livewire or Inertia (React, Vue, Svelte) starter kits, Next.js, Astro, ASP.NET (Razor Pages, MVC, Web API, Blazor), an empty PHP folder or any Composer package; database, migrations, frontend build and Git included.
- **Several PHP versions:** 7.4 to 8.5 through Homebrew, a PHP-FPM pool per version, php.ini, modules, `pecl install`.
- **Several Node versions:** from nodejs.org, plus Homebrew's.
- **.NET:** SDKs 8, 9 and 10 through Homebrew, per site; ASP.NET projects run with `dotnet watch` behind Caddy.
- **Mail:** a built-in SMTP catcher on `127.0.0.1:2525` with HTML, text and source views and attachments. New Laravel projects send their mail to it.
- **Services:** MySQL, MariaDB, PostgreSQL, Redis, Valkey, Memcached, Mailpit, Meilisearch, MinIO through `brew services`. Starting one stops another on the same port.
- **Database:** browse and edit SQLite, MySQL and PostgreSQL: sorting, paging, cell editing, SQL console.
- **Proxy sites:** `name.test` for anything listening on a local port (Vite, Rails, Go, Docker containers).
- **Terminal:** a `nerd` command like Herd's `herd`: park, link, open, secure, PHP version per site, proxy sites, start at login.
- **Debug:** a Debug window (⇧⌘D) that follows Caddy, PHP-FPM, PHP errors, Laravel logs and dev servers live, with level and text filters; Xdebug on or off per PHP version.
- **Dumps:** `dump()` and `dd()` from any site using symfony/var-dumper (Laravel, Symfony) show up live in the Debug window, grouped by request, with the calling file and line one click from the editor. Optionally Artisan, Tinker and test dumps too.
- **Exceptions:** errors from each Laravel site's `storage/logs/laravel.log` as a browsable list with the message, the source and a stack trace whose vendor frames fold away.
- **MCP:** `Nerd mcp` is a Model Context Protocol server, so AI tools such as Claude Code and Cursor can list sites, control services, read logs, query databases, read caught mail, run artisan and write Docker files.
- **Deployment:** Docker setups for Dokploy, see below. Forge needs nothing extra.
- **Appearance and language:** Liquid Glass on macOS 26, system, light or dark; English and Turkish.

## Deployment: Dokploy and Forge

From a site's Deployment section (or "Add Docker files" in the wizard) Nerd writes a production `Dockerfile`, `docker-compose.yml` and `.dockerignore`. PostgreSQL, MySQL and Redis can be added to any project; the app gets `DATABASE_URL` / `REDIS_URL` (Node), `ConnectionStrings__*` (.NET) or `DB_*` / `REDIS_*` (Laravel):

- **Laravel:** the [serversideup/php](https://serversideup.net/open-source/docker-php/) image (nginx and PHP-FPM), migrations on start, `queue` and `scheduler` services, MySQL, PostgreSQL or SQLite according to `.env` (SQLite on the persistent `storage` volume) and Redis when it is used.
- **Next.js:** built with `output: "standalone"`.
- **Astro:** static sites served by nginx, SSR (`@astrojs/node`) by Node.
- **ASP.NET:** built with the .NET SDK image and run on the ASP.NET runtime image.

In Dokploy, create a Compose application, connect the repository and add a domain to the `app` service. Put secrets such as `APP_KEY` and `DB_PASSWORD` in the Environment tab.

From the command line:

```bash
/Applications/Nerd.app/Contents/MacOS/Nerd docker ~/Sites/my-app --db pgsql --redis
```

## Terminal

Nerd installs a `nerd` command in `~/.nerd/bin`. Changes apply to a running Nerd at once, or on its next launch.

```bash
nerd park ~/Code            # every folder inside becomes name.test
nerd link my-app            # link the current folder as my-app.test
nerd sites                  # list sites
nerd open                   # open the current folder's site
nerd secure                 # HTTPS for the current site
nerd use php@8.4            # PHP version for the current site
nerd php artisan migrate    # run with the site's PHP version
nerd proxy api 8080         # api.test → localhost:8080 (Vite, Rails, Go, Docker…)
nerd startup on             # start Nerd at login
nerd help                   # everything else
```

## MCP

Add Nerd to Claude Code from Settings → MCP, or by hand:

```bash
claude mcp add --scope user nerd -- /Applications/Nerd.app/Contents/MacOS/Nerd mcp
```

Other clients (Cursor, Windsurf, …):

```json
{ "mcpServers": { "nerd": { "command": "/Applications/Nerd.app/Contents/MacOS/Nerd", "args": ["mcp"] } } }
```

Tools: `list_sites`, `get_site`, `environment`, `list_services`, `service_action`, `list_logs`, `read_log`, `list_tables`, `query_database`, `list_mail`, `read_mail`, `artisan`, `generate_docker`.

To send a Laravel app's mail to Nerd:

```dotenv
MAIL_MAILER=smtp
MAIL_HOST=127.0.0.1
MAIL_PORT=2525
```

## How it works

| Part | How |
|---|---|
| Web server | Caddy (`~/.nerd/Caddyfile`); on macOS ports 80 and 443 need no root |
| PHP | One `php-fpm` per version, on a Unix socket |
| Next.js / Astro / .NET | `npm run dev` or `dotnet watch` on a fixed port per site, reverse proxied by Caddy |
| DNS | A small UDP DNS server in the app (127.0.0.1:53535) plus `/etc/resolver/test`. Not needed with `.localhost` |
| Mail | SMTP server in the app; messages in `~/.nerd/mail/*.eml` |
| Dumps | `~/.nerd/php/prepend.php` (PHP-FPM `auto_prepend_file`) sends each dump to `127.0.0.1:9913` |
| HTTPS | Caddy `tls internal`; trust the root certificate from Settings |
| Updates | GitHub releases, verified against the developer's signature before they are installed |
| Config | `~/.nerd/config.json`, logs in `~/.nerd/logs` |

## Build from source

Xcode 16 or later:

```bash
git clone https://github.com/mdenizay/nerd.git
cd nerd
./scripts/build-app.sh
open build/Nerd.app
```

`open build/Nerd.app --args --window --page=sites` opens the window on a given page. The interface strings live in `Resources/Localizable.xcstrings` (source language Turkish); `scripts/sync-strings.sh` collects new ones from the code.

Icons: [Lucide](https://lucide.dev) (ISC), fetched with `tools/fetch-icons.sh`. Technology logos: [Simple Icons](https://simpleicons.org), fetched with `tools/fetch-brands.sh`; see [NOTICE.md](NOTICE.md).

## License

[MIT](LICENSE)
