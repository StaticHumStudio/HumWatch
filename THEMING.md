# HumWatch Theming Guide

HumWatch uses CSS custom properties for all visual styling, making it straightforward to create new themes or modify existing ones.

## Built-in Themes

| Theme | File | Description |
|-------|------|-------------|
| Default | `static/css/theme.css` | Void black with gold and teal accents |
| Light | `static/css/themes/theme-light.css` | Warm off-white with blue accents |
| Terminal | `static/css/themes/theme-terminal.css` | Green-on-black, monospace, scanlines |

## Creating a Custom Theme

### 1. Copy a starter file

Copy `static/css/themes/theme-light.css` to a new file:

```
static/css/themes/theme-mytheme.css
```

### 2. Override the CSS custom properties

Every visual property is controlled by a `--hw-*` variable. At minimum, override these groups:

**Backgrounds**
```css
:root {
    --hw-bg-primary: #f5f3ef;     /* Page background */
    --hw-bg-secondary: #eae7e1;   /* Secondary surfaces */
    --hw-bg-card: #ffffff;        /* Card backgrounds */
    --hw-bg-sidebar: #1e1e28;    /* Sidebar background */
    --hw-bg-input: #eae7e1;      /* Form input backgrounds */
    --hw-bg-hover: rgba(0,0,0,0.04); /* Hover state */
}
```

**Text**
```css
:root {
    --hw-text-primary: #1a1a2e;   /* Main text */
    --hw-text-secondary: #555566; /* Labels, descriptions */
    --hw-text-tertiary: #888899;  /* Muted text */
    --hw-text-sidebar: #c8c8d0;  /* Sidebar text */
}
```

**Accents**
```css
:root {
    --hw-accent-primary: #3b82f6;   /* Primary accent (buttons, active states) */
    --hw-accent-secondary: #2dd4a8; /* Secondary accent */
    --hw-accent-gold: #d4a843;      /* Gold accent */
}
```

**Status colors**
```css
:root {
    --hw-status-ok: #22c55e;       /* Normal/good */
    --hw-status-warn: #f59e0b;     /* Warning */
    --hw-status-critical: #ef4444; /* Critical/error */
    --hw-status-offline: #94a3b8;  /* Offline/disabled */
}
```

**Gauge colors**
```css
:root {
    --hw-gauge-track: #d4d0ca;  /* Gauge background arc */
    --hw-gauge-cold: #3b82f6;   /* Low value color */
    --hw-gauge-warm: #f59e0b;   /* Medium value color */
    --hw-gauge-hot: #ef4444;    /* High value color */
}
```

### 3. Register the theme

Open `static/js/utils/theme.js` and add your theme to the `available` object:

```javascript
mytheme: { name: 'My Theme', css: '/static/css/themes/theme-mytheme.css' },
```

### 4. Optional: Add component overrides

Beyond CSS variables, you can override specific component styles. The theme file is loaded after the base styles, so selectors with equal specificity will win:

```css
/* Example: rounded cards */
.hw-card {
    border-radius: 16px;
    border: 2px solid var(--hw-accent-primary);
}

/* Example: custom scrollbar */
::-webkit-scrollbar-thumb {
    background: var(--hw-accent-primary);
}
```

## CSS Variable Reference

| Variable | Used For |
|----------|----------|
| `--hw-bg-primary` | Page/body background |
| `--hw-bg-secondary` | Table headers, secondary surfaces |
| `--hw-bg-card` | Card backgrounds |
| `--hw-bg-sidebar` | Sidebar background |
| `--hw-bg-input` | Input field backgrounds |
| `--hw-bg-hover` | Hover state overlay |
| `--hw-text-primary` | Main text color |
| `--hw-text-secondary` | Labels, subtitles |
| `--hw-text-tertiary` | Muted/hint text |
| `--hw-text-sidebar` | Sidebar nav text |
| `--hw-accent-primary` | Primary interactive elements |
| `--hw-accent-secondary` | Secondary highlights |
| `--hw-accent-gold` | Gold branding accent |
| `--hw-status-ok` | Success/normal indicators |
| `--hw-status-warn` | Warning indicators |
| `--hw-status-critical` | Critical/error indicators |
| `--hw-status-offline` | Offline/disabled state |
| `--hw-border-color` | Primary borders |
| `--hw-border-subtle` | Subtle dividers |
| `--hw-shadow-card` | Card drop shadow |
| `--hw-shadow-elevated` | Elevated element shadow |
| `--hw-gauge-track` | Gauge background arc |
| `--hw-gauge-cold` | Gauge low-value color |
| `--hw-gauge-warm` | Gauge mid-value color |
| `--hw-gauge-hot` | Gauge high-value color |
| `--hw-scrollbar-thumb` | Scrollbar handle |
| `--hw-scrollbar-track` | Scrollbar track |
| `--hw-font-family` | Primary font stack |
| `--hw-font-mono` | Monospace font stack |
| `--hw-font-size-xs` through `--hw-font-size-xl` | Font sizes |
| `--hw-space-xs` through `--hw-space-xl` | Spacing scale |
| `--hw-radius-sm` through `--hw-radius-lg` | Border radii |

## Tips

- The gauge component reads `--hw-gauge-cold`, `--hw-gauge-warm`, `--hw-gauge-hot` at render time, so changing these variables will affect new gauge draws.
- Chart.js colors are read from CSS variables via `getComputedStyle` when charts are created. Use the theme switcher or call `HumWatch.charts.resetColors()` after changing themes.
- The sidebar always uses `--hw-bg-sidebar` and `--hw-text-sidebar` — you can keep the sidebar dark even in a light theme.
- Remove `background-image` on `body` if you don't want the noise texture from the default theme.
