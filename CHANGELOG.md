# Changelog

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
