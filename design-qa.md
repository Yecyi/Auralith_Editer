# Auralith Agent sidebar design QA

## Evidence

- Source visual truth: `/var/folders/jc/dbd6xttx1td3rr9ylyr9d_xr0000gp/T/TemporaryItems/NSIRD_screencaptureui_NqKCiM/截屏2026-07-25 下午7.59.29.png`
- Source sidebar crop: `/private/tmp/auralith-sidebar-redesign-2026-07-25/01-current-sidebar-crop-406x876.png`
- Structural reference: `/private/tmp/auralith-sidebar-redesign-2026-07-25/02-vscode-chat-view-reference.png`
- Rendered implementation: `/private/tmp/auralith-sidebar-redesign-2026-07-25/03-setup-after-380x876.png`
- Combined full-view comparison: `/private/tmp/auralith-sidebar-redesign-2026-07-25/05-comparison-current-new-vscode.png`
- Supplemental light-theme capture: `/private/tmp/auralith-sidebar-redesign-2026-07-25/04-light-setup-1280x720.png`
- Supplemental unsupported-editor capture: `/private/tmp/auralith-sidebar-redesign-2026-07-25/04-unsupported-night-1280x720.png`
- Reinstalled native app capture: `/private/tmp/auralith-sidebar-redesign-2026-07-25/06-reinstalled-native-sidebar.png`

## Normalization

- State: model setup required, Simplified Chinese, dark/night theme, reduced motion.
- Source pixels: full screenshot 1916 × 960; reviewed sidebar crop 406 × 876.
- Implementation pixels and CSS size: 380 × 876 at device scale factor 1.
- The implementation was captured with a temporary CSS sizing frame only; that frame was removed after capture. Component styles and product state were unchanged.
- No density resampling was used in the combined comparison. The 26 px width reduction is intentional product work, not a density mismatch.
- The full-view comparison keeps all three panels at original pixel density. A focused crop was not needed because the header, setup copy, status, borders, and composer remain legible at 1:1 scale.

## Comparison history

### Pass 1

- P1 — The original blocked state repeated the same problem in the header badge, global error banner, setup card, and disabled feature cards.
- P1 — Rounded nested cards, panel inset, radius, blur, and shadow made the sidebar read as a floating mini-app rather than editor chrome.
- P2 — Model selection and action controls were split across the header, setup card, disabled document sections, and bottom question area.
- P2 — Expected setup was styled as a destructive error, increasing alarm without helping recovery.

Fixes applied:

- Collapsed setup into one centered state plus one bottom model-settings action.
- Replaced card stacks with a continuous context/conversation surface and a fixed composer.
- Moved model selection into the composer and retained only a compact status in the header.
- Changed setup status from destructive red to warning yellow; runtime failures still use the error treatment.
- Made the host panel flush to the editor edge with a single divider, no panel radius, no inset, no blur, and no shadow.
- Removed scale/press motion and retained reduced-motion and forced-colors behavior.

### Pass 2

Post-fix evidence: `/private/tmp/auralith-sidebar-redesign-2026-07-25/05-comparison-current-new-vscode.png`

- No remaining P0, P1, or P2 visual finding.
- Typography: the sidebar uses the shared Auralith/ONLYOFFICE font stack, compact 11–14 px hierarchy, consistent line heights, and safe truncation.
- Spacing and layout: the 40 px header, continuous body, and fixed composer establish the same structural rhythm as the VS Code reference without copying its branding.
- Colors and tokens: canvas, surface, border, text, accent, warning, and focus states resolve through shared theme tokens in light and dark themes.
- Image and icon fidelity: the existing Auralith product mark is reused; no placeholder imagery, emoji, or decorative CSS art was introduced.
- Copy: setup text now describes one recovery path and removes duplicated technical error language.
- Accessibility: semantic regions and labels are present, keyboard focus reaches the settings action, Enter activates it, setup status is announced politely, and no horizontal overflow is expected at the tested narrow contract.

## Runtime checks

- Primary interaction tested: keyboard focus and Enter activation of the model-settings shortcut.
- States visually inspected: dark setup, light setup, and unsupported editor.
- Browser console: no page errors or application error logs.
- Automated validation: TypeScript passed; focused presentation tests passed 3/3; document-reader tests passed 185/185; production Vite build passed.
- Native install: 302/302 bundle files match the build, host CSS/JS hashes match source, and the isolated Test app passes strict deep code-sign verification.
- Native interaction: the isolated app was restarted, the DOCX fixture loaded, and the redesigned Agent sidebar opened successfully in the editor.

## Residual P3

- The current host is a flush fixed dock rather than a true layout-resizing native editor pane. A future HBox/resizable integration can improve document-canvas coexistence without changing the new Reader component contract.

final result: passed
