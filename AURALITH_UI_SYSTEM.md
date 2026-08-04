# Auralith UI system

This document defines the extension contract for Auralith Agent UI. It applies
to the standalone Agent, the document Reader, the embedded model settings view,
and the editor-owned launcher/panel host.

## Goals

- Preserve the visual character of the active ONLYOFFICE theme.
- Keep feature code independent from palette, density, typography, and motion.
- Make compact office surfaces readable at narrow widths and high zoom.
- Treat keyboard focus, reduced motion, RTL, and forced colors as base behavior.
- Support incremental migration without breaking legacy CSS variable consumers.

## Token layers

The Agent bundle uses three layers:

1. `src/styles/foundations.css` owns fonts, the type scale, spacing, radii,
   control heights, shadows, and motion curves. It also owns the shared
   material behavior: `--auralith-glass-blur`, `--auralith-glass-saturate`,
   and the `--auralith-ease-spring` soft-spring curve used for entrances and
   material responses.
2. `src/styles/semantic.css` maps the seven existing editor themes onto stable
   surface, text, border, accent, success, warning, and danger roles. It also
   resolves the material tokens per theme family: `--auralith-material-mica`
   (near-opaque tinted chrome, e.g. the sticky agent-tab header and composer
   dock), `--auralith-material-acrylic` (stronger translucency reserved for
   overlays such as the floating history panel),
   `--auralith-material-glass` (floating controls such as the composer field),
   plus `--auralith-glass-edge` (luminous inner highlight),
   `--auralith-glass-stroke` (hairline boundary), and
   `--auralith-glass-tint` (faint accent wash). Dark themes lift the surface
   and strengthen the edge highlight; light themes keep translucency calm.
3. `src/styles/components.css` owns interaction behavior shared by every
   surface, including focus and motion preferences.

Feature and component styles should consume `--auralith-*` tokens. Existing
theme and `--reader-*` properties remain compatibility aliases during
migration; new hard-coded theme colors are not part of the supported contract.

Translucency is only applied where content can physically pass beneath the
surface: the agent-tab header is sticky inside the scroll port so the thread
diffuses under the mica, and overlays use acrylic. In-flow surfaces keep
near-opaque tints. `forced-colors` disables blur, translucency, and glass
shadows; reduced motion collapses spring entrances through the shared
duration tokens.

Theme IDs are registered once in `src/styles/theme-registry.ts`. Code that
validates, applies, or classifies a theme must import the registry rather than
maintaining another allow-list.

## Customization contract

Components consume resolved `--auralith-*` tokens. Hosts customize color
resolution from above the Agent root through inherited
`--auralith-custom-color-*` inputs; this keeps a theme class from accidentally
overwriting a host choice. Foundation tokens that are not remapped by themes
can be overridden directly:

```css
.customer-agent-theme {
  --auralith-custom-color-accent: #6d4aff;
  --auralith-custom-color-accent-hover: #7d60ff;
  --auralith-custom-color-accent-pressed: #5637df;
  --auralith-custom-color-on-accent: #ffffff;
  --auralith-radius-lg: 10px;
  --auralith-panel-padding: 16px;
  --auralith-font-sans: "Inter", system-ui, sans-serif;
}
```

The same input pattern is available for canvas, surfaces, borders, text,
success, warning, danger, and focus-ring roles. Customizers should override a
complete interactive color set (base, hover, pressed, and foreground) and
retain accessible contrast. Material resolution follows the same contract
through `--auralith-custom-material-mica`, `--auralith-custom-material-acrylic`,
`--auralith-custom-material-glass`, `--auralith-custom-glass-edge`,
`--auralith-custom-glass-stroke`, and `--auralith-custom-glass-tint`.

Reader URLs accept two deterministic presentation options:

- `density=compact|comfortable`
- `motion=reduce`

The browser preference `prefers-reduced-motion: reduce` always takes priority.
The editor host exposes a parallel, deliberately small contract with
`--auralith-agent-*`; panel width, font, radii, motion, and layer values can be
overridden without editing host CSS.

## Component rules

- Interactive controls use a minimum 32px hit area unless they are embedded in
  a larger labeled target.
- Icon-only buttons need a translated `aria-label` or title. Never treat an
  internal icon asset name as user-facing copy. During migration, decorative
  icons should use `Icon` rather than `IconButton`.
- Never remove `focus-visible` without replacing it with the shared accent ring.
- Informational text must be at least 11px/16px. Body copy defaults to 13px/20px.
- Use semantic status roles and pair color with text or shape.
- Animate opacity and transforms only. Use the shared 80/120/180/240ms timing
  scale; no essential state may depend on animation.
- Layout uses logical properties (`inline-start`/`inline-end`) so RTL does not
  require a second layout.

## Surface boundaries

- `Layout` owns the standalone Agent shell and shared primitives.
- `ReaderApp` owns document workflow state. Presentational pieces should move
  into `document-reader/ui` components; `ReaderHeader` and `AuralithMark` are
  the first extracted primitives.
- `LlmSettingsApp` owns the embedded model and permission workflow. Its entry
  styles are imported once by `reader-main.tsx`, so import order cannot vary by
  view.
- `auralith-agent-host.css/js` owns editor integration only. It may size,
  launch, theme, and localize the iframe, but should not duplicate Reader UI.

## Migration route

1. Migrate Button, IconButton, Input, Checkbox, Radio, Toggle, and dialogs to
   the shared foundation and interaction tokens.
2. Split `ReaderApp` into controller and presentational sections without
   changing its document bridge or task state machine.
3. Replace repeated component mappings in the seven theme files with one shared
   component mapping layer, leaving only palettes in individual themes.
4. Add a stable editor header slot and Advanced Settings slot in `web-apps`,
   then move from the fixed flyout toward a layout-aware docked sidebar.
5. Replace embedded fixed provider dialogs with an inline settings flow or a
   host-owned native dialog.

## Required regression matrix

Validate Reader, model settings, standalone Agent, and editor host in:

- white, gray, night, and contrast-dark themes;
- 420px, 370px, 320px, and 280px widths;
- Chinese, English, and at least one RTL locale;
- keyboard-only, reduced-motion, and forced-colors modes;
- empty, setup-required, loading, ready, warning, error, and long-content
  states.

Run Agent checks with Node.js 20. Build with `npx vite build`; do not use the
legacy root build command that overwrites tracked deploy assets.
