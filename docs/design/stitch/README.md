# Stitch mockups — dziegielew.ski

Visual reference only. The HTML files are Stitch exports (Tailwind CDN, Google
Fonts, AI-generated stand-in portrait) and must **not** be shipped. The
implementation is one hand-written CSS file using the tokens below.

## Stitch identifiers

| Item | ID |
|------|----|
| Project | `16059708166058068666` ("dziegielew.ski — personal homepage") |
| Design system | `assets/10877898059779442829` ("dziegielew.ski minimal") |
| Home, desktop | screen `93bb3abd513e421f8b24c373f8a4a4dd` |
| Home, mobile | screen `9decbdcb7b654bb78928e25c679a38fd` |
| CV, desktop | screen `2866a593d0fa4faaa2c623b43a987003` |

Stitch also created a helper screen `b8dd5e9aab7b44a79d032d23edf68943` (the
generated stand-in portrait); ignore it.

## Files

| File | Notes |
|------|-------|
| `home-desktop.html` / `.png` | 1280 px viewport |
| `home-mobile.html` / `.png` | 500 px viewport (headless Chrome minimum width; layout is fluid, so 390 px looks the same) |
| `cv-desktop.html` / `.png` | 1280 px viewport, contains an `@media print` block worth reusing |

PNGs were rendered locally with headless Google Chrome from the exported HTML,
not downloaded from Stitch (the Stitch file API needs an OAuth token that
the shell permissions block). One local fix in `home-desktop.html`: Stitch's
Tailwind config mapped `rounded-full` to `0.75rem`, so the photo was a
rounded square; changed to `9999px` to match the intended circle.

## Color tokens

Light theme (from the mockups, stone neutrals + one teal accent):

| Token | Light | Dark (proposal) | Use |
|-------|-------|-----------------|-----|
| `--color-background` | `#FAFAF9` | `#1C1917` | page background (print: `#FFFFFF`) |
| `--color-text` | `#1C1917` | `#E7E5E4` | headings, body text |
| `--color-text-muted` | `#57534E` | `#A8A29E` | role line, about paragraph, labels |
| `--color-text-subtle` | `#78716C` | `#8A837E` | years, section headings, footer |
| `--color-border` | `#E7E5E4` | `#3A3532` | hairline dividers |
| `--color-accent` | `#0F766E` | `#5EC2B7` | links, "CV →" outline, company names |
| `--color-accent-hover-background` | `#F0FDFA` | `#16302D` | hover fill of the "CV →" link |

Contrast: accent `#0F766E` on `#FAFAF9` ≈ 5.3:1, dark accent `#5EC2B7` on
`#1C1917` ≈ 8:1. The CV mockup uses `#A8A29E` for section headings and years
on white (≈ 2.5:1, too low) — use `--color-text-subtle` instead.

The mockups disagree on the background (home desktop `#FAFAF9`, mobile and CV
`#FFFFFF`); use `#FAFAF9` on screen and `#FFFFFF` in print.

Dark mode: swap the token values inside
`@media (prefers-color-scheme: dark) { :root { … } }`; nothing else changes.

## Typography

Stitch only offers web fonts (Inter, Plus Jakarta Sans and JetBrains Mono were
used); the implementation uses system stacks instead:

```
--font-sans: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
--font-mono: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
```

| Role | Size / weight / line height | Notes |
|------|-----------------------------|-------|
| Name (H1) | 30px / 700 / 1.2, letter-spacing -0.025em | 24px below 640px |
| Role line | 18px / 500 | muted; 15–16px on mobile and CV |
| Location | 14px / 400 | subtle, optional pin glyph (inline SVG) |
| Body / about | 17px / 400 / 1.625 | 15–16px on mobile |
| Link rows, CV entries | 14–16px / 400–500 | role titles in italic on CV |
| Section heading (CV) | 12px / 600, uppercase, letter-spacing 0.1em | |
| Years (CV), footer | 12px mono, `font-variant-numeric: tabular-nums` | |
| Wordmark, navigation | 14px / 600 (wordmark), 400 (links) | current page bold or underlined |

The only terminal detail: the footer line
`$ whoami → jabbas · © 2026 Grzegorz Dzięgielewski` in `--font-mono`.

## Spacing and layout

- Single centered column: home `max-width: 42rem` (672px), CV `max-width: 47.5rem` (760px); horizontal padding 24px (40px on CV desktop).
- Header: wordmark left, "Home" / "CV" text links right, 40px vertical padding on home; plain text links, no hamburger (works without JavaScript at every width).
- Vertical rhythm: 48px between home sections; 48px between CV sections, each CV section after the first starts with a hairline top border + 24px padding.
- Home intro: photo 160px circle (120px mobile, stacked and centered), 40px gap to text block on desktop.
- Link list: rows with `label` left (muted) and `value` right, 16px vertical padding (14px mobile), 1px `--color-border` dividers top/between.
- "CV →" link: 1px accent border, 4px radius, 8px × 16px padding (full width, 12px vertical on mobile), no fill.
- CV header: name/role/location/contact links left, 120px circular photo right; 32px bottom padding + hairline border.
- CV timeline: CSS grid `grid-template-columns: 130px 1fr; column-gap: 24px; row-gap: 14px`; collapses to one column below 640px.
- Knowledge list: two columns from 768px up.
- Radius: 4px (buttons), 50% (photo). No shadows, no gradients, no filled cards.
- Spacing scale (px): 4, 8, 12, 16, 24, 32, 40, 48, 64.

## Print (CV)

From the CV export: `@page { size: A4; margin: 1.5cm; }`, white background,
black text, 11pt base size, hide site header and footer, links in text colour
without underline, `break-inside: avoid` on each section (except the long
experience list, which should be allowed to break between rows).
