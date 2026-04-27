# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Government transparency portal (Portal de Transparência) for Prefeitura Municipal de Arroio dos Ratos (RS, Brazil), built to meet PNTP 2026 (Programa Nacional de Transparência Pública) compliance requirements. The project is a collection of standalone HTML pages designed to be embedded in a WordPress site.

## No Build System

This is a **pure static HTML/CSS/JS project** — no npm, no bundler, no compiler, no linter, no test runner. To develop:
- Open HTML files directly in a browser, or
- Serve with any static server (e.g., `python -m http.server 8000` or VS Code Live Server)

There are no commands to run.

## WordPress Integration

Pages are designed to be embedded in WordPress via HTML blocks or custom page templates. The key integration point is the WordPress REST API:

- `atos-oficiais-v4.html` auto-detects the API base URL at runtime using `window.location` and falls back to a hardcoded production URL
- API calls: `/wp-json/wp/v2/posts` and `/wp-json/wp/v2/categories`
- Category slugs are configured in the `CONFIG` object at the top of `atos-oficiais-v4.html`

## Architecture

### Static compliance pages
Most pages (`acessibilidade.html`, `politica-de-privacidade.html`, `politica-de-cookies.html`, `atalhos-navegacao.html`, `encarregado-lgpd.html`, `alto-contraste.html`, `mapa-do-site.html`, `horario-de-atendimento.html`) are static HTML with inline CSS and no meaningful JavaScript.

### `atos-oficiais-v4.html` — the main data application (1,412 lines)
The most complex page. Its JavaScript (wrapped in an IIFE) follows this pipeline:
1. **Init** — detects API URL → fetches category IDs by slug → paginated parallel fetch of posts (up to 20 pages × 100 posts via `Promise.all`)
2. **Transform** — `postParaAto()` normalizes each API post; `classificar()` applies 50+ regex patterns to auto-assign `grupo`/`tipo` from the post title
3. **State** — `dadosOriginais[]` (immutable) and `dadosFiltrados[]` (filtered view)
4. **UI** — `prepararFiltros()` populates `<select>` dropdowns; `renderTabela()` builds table rows
5. **Filter** — `aplicarFiltros()` applies text search (with diacritic normalization) + dropdown filters
6. **Export** — six formats: CSV (UTF-8 BOM for Excel), XLSX (SheetJS from CDN), JSON, ODS (SheetJS), XML (entity-escaped), PDF (`window.print()`)

### Form pages
- `pesquisa-satisfacao-formulario.html` — satisfaction survey; persists to `localStorage` under key `pesquisa_respostas` as JSON with auto-generated ID (`PS-YYYY-NNNNN`)
- `esic-formulario.html` — public information request form; client-side validation only; backend integration not yet implemented
- `esic-painel-interno (1).html` — internal e-SIC dashboard; demo-only client-side login, mock data

### Design system
All pages share the same CSS variable palette defined inline in each `<style>` block:
- `--azul-escuro: #0b3d6e`, `--azul: #0f5ea8`, `--azul-claro: #dbeafe`, `--azul-suave: #f0f6ff`
- `--verde: #166534`, `--verde-bg: #dcfce7`, `--vermelho: #dc2626`
- Responsive via `@media (max-width: 640px)` and `@media (max-width: 900px)`
- Print styles (`@media print`) used for PDF export in `atos-oficiais-v4.html`

## External Dependency

SheetJS (for XLSX/ODS export) is loaded from CDN in `atos-oficiais-v4.html`:
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script>
```
If offline or CDN is unavailable, XLSX and ODS export will silently fail; the other four export formats (CSV, JSON, XML, PDF) have no external dependencies.

## PNTP 2026 Compliance Context

The file `analise-pntp-2026-arroio-dos-ratos.md` is a compliance audit. Many transparency items (spending, HR, procurement, health, education) exist as pages but lack real-time data, filtering, export, and historical series — these are known gaps awaiting backend integration.

## Key Constraints

- **Vanilla JS only** — no frameworks; target broad browser compatibility (ES5-era patterns, `async/await` only in `atos-oficiais-v4.html`)
- **Forms are demo-only** — `esic-painel-interno` login and `esic-formulario` submission are client-side only; real deployment needs server-side validation and CSRF protection
- **No authentication** on public pages; `esic-painel-interno` is a UI prototype, not a secure system
- XSS prevention is implemented in export functions (`escHTML`, `escAttr`, `escXML` helpers in `atos-oficiais-v4.html`) — preserve these when editing
