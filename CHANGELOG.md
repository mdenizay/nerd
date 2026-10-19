# Changelog

## 0.10.1

- Use the Liquid Glass app icon on macOS 26 and the brand colour as the accent colour (CFBundleIconName and NSAccentColorName were missing from Info.plist)

## 0.10.0

- A Liquid Glass app icon made in the Icon Composer format: a layered glass cube that follows the system's clear, dark and tinted icon styles on macOS 26; earlier versions get an icon rendered from it
- Menu bar panel in native Liquid Glass: a tinted glass power button, glass chips and a prominent glass New Project button in one glass container
- Primary actions use the glass prominent button style; content fades softly under the transparent toolbar

## 0.9.1

- Clicking Nerd's icon (Finder, Dock, Launchpad) opens the main window, also while Nerd only lives in the menu bar; started at login it stays quiet
- A new menu bar panel: a power button with the state of the stack, sites and services under one switcher, PHP and Node switchers and New Project at the bottom

## 0.9.0

- Dumps: `dump()` and `dd()` from sites served by Nerd appear live in the Debug window, with the site, request and file:line
- Exceptions: Laravel log entries parsed into exceptions with their stack traces in the Debug window
- Composer is managed: when none is installed, Nerd downloads the official composer.phar into ~/.nerd/bin (SHA-256 verified), installs it before creating a project if needed, and can update it from the PHP page

## 0.8.0

- `nerd` terminal command (installed in ~/.nerd/bin): park, forget, link, unlink, sites, open, secure, use / isolate a PHP version per site, php and composer with the site's PHP, logs, proxy, docker, mcp, startup; changes reach a running Nerd at once
- Proxy sites: name.test → localhost:PORT for apps Nerd does not detect, from the Sites toolbar or `nerd proxy`
- Start Nerd at login, from Settings or `nerd startup on`

## 0.7.7

- Menu bar panel: the app icon and a status line in the header, each site's runtime on the right, a status dot for running services, PHP and Node logos, a steadier rhythm

## 0.7.6

- The menu bar panel follows macOS's own menu bar extras: Nerd with its switch, sites, running services, PHP and Node versions, and New Project, Open Nerd and Quit at the bottom

## 0.7.5

- The menu bar shows a panel again: status and the web server switch, quick actions (new project, database, mail, debug), sites with logos and actions, service switches, PHP and Node switchers

## 0.7.4

- PHP 8.5: deprecation notices raised before a framework sets up its error handling (Laravel's `PDO::MYSQL_ATTR_SSL_CA` in config/database.php) no longer show up in pages; PHP-FPM pools use `E_ALL & ~E_DEPRECATED` and frameworks still raise the level themselves
- New Laravel projects get config/database.php updated to `Pdo\Mysql::ATTR_SSL_CA` on PHP 8.5

## 0.7.3

- New project is one native form: a template gallery with logos (Laravel, JavaScript, .NET, Other), project, runtime and options; Create sits in the toolbar
- While creating, the page shows progress with details, then actions to open the site, the editor or the site's settings

## 0.7.2

- The toolbar no longer spills over the top of the sidebar; content runs under the toolbar

## 0.7.1

- The status card at the top of the sidebar has no box behind it and lines up with the sidebar icons

## 0.7.0

A new interface in the Laravel Herd and System Settings idiom:

- Sidebar with a status card and the web server switch on top, sections with small coloured icons
- Native grouped forms everywhere, page titles and actions in the native toolbar (Liquid Glass on macOS 26)
- Sites as a table (site, address, runtime, HTTPS, folder) with an inspector for the selected site, a context menu and toolbar search
- The menu bar is a native menu: web server, sites with their actions, PHP / Node / .NET switchers, service toggles, quick windows

## 0.6.2

- Text, rows, headers and spacing are back to their 0.6.0 sizes; only the default window is smaller (980 × 620)
- Larger technology logos in the new project wizard

## 0.6.1

- More compact: a slimmer title bar, the wizard's steps in the toolbar, tighter headers, rows and sections, a smaller default window
- Real technology logos (Simple Icons) for templates, sites, services and runtimes: Laravel, Livewire, React, Svelte, Next.js, Astro, .NET, Blazor, PHP, Node.js, MySQL, MariaDB, PostgreSQL, Redis, Meilisearch, MinIO, Docker, Composer

## 0.6.0

- MCP server: `Nerd mcp` lets AI tools (Claude Code, Cursor, …) list sites, control services, read logs, query site databases, read caught mail, run artisan and write Docker files; one-click setup for Claude Code in Settings
- Debug window (⇧⌘D): live Caddy, PHP-FPM, PHP error, Laravel and dev server logs with level and text filters
- Xdebug on or off per PHP version (installs it with pecl when needed)
- Docker: add PostgreSQL, MySQL or Redis to any project, with connection settings passed to the app
- Lucide icon set, the brand colour as the system accent, a seamless title bar
- Redesigned menu bar panel: status, quick actions, sites and services in glass cards, PHP and Node switchers

## 0.5.0

- .NET: SDKs 8, 9 and 10 from Homebrew with a default and a per-site choice; ASP.NET projects are detected, run with `dotnet watch` on their own port and served at `name.test`
- New project wizard: ASP.NET Razor Pages, MVC, Web API and Blazor
- Docker files for ASP.NET projects (SDK build, ASP.NET runtime image)
- A calmer, premium look: one brand colour, neutral icons, Liquid Glass cards, chips and buttons on macOS 26 (materials on earlier versions), a metrics card on the overview
- Starting a service now finds what holds its port; a leftover Homebrew service whose program was uninstalled is stopped (this kept PostgreSQL 18 from starting)

## 0.4.0

- Colour is back, in a lighter form: soft-tinted icons for pages, sites, services and templates, coloured status chips and tags
- Rows are grouped in rounded cards; every page header carries its own icon
- Works the same in light and dark

## 0.3.0

- A quieter, more compact interface: one header bar per page, dense rows with hairline separators, monochrome icons, native sidebar
- Services, PHP and Node are lists with Installed and Available sections; services switch on and off inline
- Site settings, mail, deployment and logs on one compact page

## 0.2.0

- English interface, alongside Turkish; pick the language in Settings or follow the system
- Automatic updates from GitHub releases, checked against the developer signature
- Delete a project: the folder goes to the Trash, the database can be dropped too
- Starting a service stops another one on the same port (PostgreSQL 17/18, MySQL/MariaDB, Redis/Valkey)
- Uninstalling PHP, Node or a service now asks first
- Docker files and generated comments in English

## 0.1.0

The first release.

- Menu bar panel and main window for a local PHP and JavaScript environment
- Sites from parked folders as `name.test`, with Caddy, PHP-FPM per version, a built-in DNS resolver and local HTTPS
- Laravel, plain PHP, Next.js and Astro projects; Node apps run their dev server behind Caddy
- New project wizard: Blade, Livewire, Inertia with React, Vue or Svelte, Next.js, Astro, empty PHP or any Composer package
- Several PHP versions from Homebrew and Node versions from nodejs.org, per site
- Services through `brew services`: MySQL, MariaDB, PostgreSQL, Redis, Valkey, Memcached, Mailpit, Meilisearch, MinIO
- Mail catcher on 127.0.0.1:2525 with HTML, text and source views
- Database browser and editor for SQLite, MySQL and PostgreSQL
- Docker setups for Dokploy: Dockerfile, docker-compose.yml and .dockerignore per project
- System, light and dark appearance
