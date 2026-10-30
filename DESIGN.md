# Design

Tokens mirror `raider_desktop/tailwind.config.js` and live in the `@theme` block of `app/assets/tailwind/application.css`.

## Tokens

| Name | Value |
|---|---|
| `--font-sans` | `"Poppins", ui-sans-serif, system-ui, sans-serif` |
| `--font-mono` | `"SF Mono", "Fira Code", ui-monospace, monospace` |
| `--color-ruby` | `#C14420` |
| `--color-ruby-lt` | `#d4374b` |
| `--color-ruby-dk` | `#7b1c2a` |
| `--color-ruby-sub` | `rgba(193, 68, 32, 0.07)` |
| `--color-ruby-glow` | `rgba(193, 68, 32, 0.12)` |
| `--color-status-ok` | `#1B7A3D` |
| `--color-status-ok-bg` | `rgba(27, 122, 61, 0.07)` |
| `--color-status-err` | `#C62828` |
| `--color-status-err-bg` | `rgba(198, 40, 40, 0.07)` |
| `--color-neutral-dark` | `#1A1A1A` |
| `--color-neutral-dk` | `#4A4A4A` |
| `--color-neutral-mid` | `#8A8A8A` |
| `--color-neutral-lt` | `#F6F6F6` |
| `--color-neutral-bdr` | `#E5E5E5` |
| `--color-neutral-wh` | `#FFFFFF` |
| `--color-accent-gold` | `#d4a017` |
| `--color-accent-gold-bg` | `rgba(212, 160, 23, 0.10)` |
| `--color-accent-salmon` | `#DA917B` |
| `--radius-sm` | `8px` |
| `--radius-md` | `10px` |
| `--radius-lg` | `16px` |
| `--radius-xl` | `20px` |
| `--shadow-card` | `0 1px 4px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04)` |
| `--shadow-card-hover` | `0 4px 16px rgba(193,68,32,0.10), 0 2px 6px rgba(0,0,0,0.06)` |
| `--shadow-elevated` | `0 8px 30px rgba(0,0,0,0.10), 0 2px 8px rgba(0,0,0,0.05)` |
| `--shadow-nav` | `0 1px 3px rgba(0,0,0,0.05)` |
| `--animate-page-enter` | `page-enter 0.25s ease-out` |

## Components

| Web | Desktop component it mirrors |
|---|---|
| `button_classes` (variants `:primary :secondary :outline :success :danger`, plus `disabled:`) | `Button` |
| `status_pill` | `StatusIndicators.StatusPill` |
| `status_dot` | `StatusIndicators.StatusDot` |
| `panel` | `StyledPanel` |
| `test_results/_card` | `TestResultCard` |

Helpers live in `app/helpers/ui_helper.rb`.

## Rule

Change a token in raider_desktop first, then mirror it here and in raider_site.
