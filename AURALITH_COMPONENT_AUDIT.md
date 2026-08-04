# Auralith component audit

Status: normative audit inventory and remediation ledger

Implementation status: **audit complete; first remediation accepted; release
blockers remain**

This document records the component boundary reviewed during the current
Auralith_Editer development cycle. It is an inventory and delivery contract,
not evidence that an implementation is complete or that a test suite has
passed.

The implementation statuses below were updated after reviewing the
working-tree changes and the validation evidence. A source file being modified
or a test being present does not by itself close an issue; only the explicitly
accepted rows are closed for their declared scope.

Related source-of-truth documents:

- `AURALITH_UI_SYSTEM.md` defines tokens, customization, accessibility, and the
  visual regression matrix.
- `AURALITH_AI_NATIVE_ARCHITECTURE.md` defines component ownership boundaries,
  the Office capability lifecycle, and release gates.
- `MACOS_HANDOFF.md` defines the current macOS build and submodule handoff.

## Audit boundary

This is a full audit of the **Auralith-owned addition and modification
boundary**, not a proposal to rewrite every upstream ONLYOFFICE component.

In scope:

- all production UI components under
  `desktop-sdk/ChromiumBasedEditors/plugins/ai-agent/src/components`;
- Auralith Agent shell and feature pages under `src/pages`;
- Auralith Reader and model-configuration surfaces;
- Auralith-owned styles, tokens, theme registration, icons, and UI helpers;
- `web-apps/apps/common/main/lib/auralith-agent-host.js` and `.css`, plus the
  Auralith host insertion points in the editor HTML files;
- Agent Harness, Office capability adapters, document bridge, host bridge, and
  Reader integration adapters that define UI behavior or capability
  availability;
- supporting provider, server, store, and host APIs where a component currently
  depends on them directly.

Out of scope:

- unmodified upstream ONLYOFFICE UI, model, controller, and SDK components;
- vendored libraries and their internal components;
- generated `deploy/auralith-agent` assets;
- a component-by-component rewrite of the tens of thousands of upstream
  ONLYOFFICE files.

If Auralith modifies an upstream component, that changed seam enters this audit
boundary. The preferred integration is a stable slot, adapter, typed extension,
or narrow upstream patch. Copying a large upstream component into an
Auralith-specific fork is not the default.

## How to read health and status

Health describes the highest currently confirmed design or runtime risk. It is
separate from implementation status.

| Health | Meaning |
| --- | --- |
| `critical` | A confirmed P0 issue can violate authorization, accessibility, localization, customization, or the shared UI contract. It blocks release. |
| `high risk` | A confirmed P1 issue makes the component unsafe to extend or unreliable for keyboard, RTL, state, or host integration. |
| `migration required` | A confirmed P2 issue or incomplete design-system migration remains. |
| `provisional foundation` | The component has a reasonable reusable boundary, but its complete API, tests, or regression evidence has not been accepted. |
| `adapter foundation` | Non-visual semantic or integration code exists, but production connection and component-boundary evidence may still be partial. |

Implementation-status values used in this document:

| Value | Meaning |
| --- | --- |
| `not started` | No candidate implementation was identified in this audit snapshot. |
| `planned` | The remediation is ordered below but is not implemented. |
| `implemented, pending validation` | Candidate working-tree code exists. It MUST NOT be described as fixed, complete, or release-ready yet. |
| `pending final update` | The final integrator must replace the value after validation and scope review. |
| `accepted` | The declared scope and evidence were reviewed successfully. A broader component-family issue may still remain open. |

## Inventory summary

The tables below cover every named Auralith production UI component and each
Auralith integration family reviewed in this cycle. Type-only files, helpers,
compound-component sub-files, and entry points are named with their owning
component family so that they cannot fall outside governance.

| Category | Reviewed boundary | Overall health | Implementation status |
| --- | --- | --- | --- |
| Foundation controls | Button, Icon, Input, selection controls, tabs, menus, dialogs, tooltips, loader | `critical` | Button/Checkbox accepted; remaining P0/P1 work open |
| Composite controls | FileItem, Markdown, Shiki, ToolFallback, ManageToolDialog | `critical` | ManageToolDialog authorization race accepted; remaining work open |
| Agent shell | App, Layout, history, chat, composer, empty and settings surfaces | `high risk` | audited; structural and localization work remains open |
| Reader and model configuration | ReaderApp, ReaderHeader, AuralithMark, LlmSettingsApp, AgentModelConfiguration | `critical` | audited; P0-04 and P1-01 remain open |
| web-apps host | editor launcher, iframe panel, theme/language transport, HTML insertion points | `high risk` | context handshake accepted; host modularization remains open |
| Harness and Office adapters | Harness, capability registry, selection formatting, Reader bridges and integration services | `adapter foundation` | registry and host-context foundation accepted; formatting remains blocked |

## Foundation-control inventory

### Button

Files:

- `src/components/button/index.tsx`
- `src/components/button/Button.utils.tsx`

Health: `critical` because it participates in P0-02; it also owns P2-01.

Confirmed concerns:

- the Auralith token and density contract was not consistently consumed;
- `scale` could escape the variant API and reach the DOM;
- native buttons did not have a safe default `type`, so placement in a form
  could create an accidental submit path;
- focus, disabled, hover, pressed, and host-custom color behavior require one
  typed variant contract.

Implementation status: `implemented and validated for the declared contract`.

The accepted implementation consumes `scale`, defaults a native button to
`type="button"`, preserves explicit submit behavior, avoids adding button-only
attributes to `asChild`, and consumes semantic tokens. Evidence covers DOM
contracts, production build, and visual parity on the 280 px Settings surface.

### Icon, IconButton, and TooltipIconButton

Files:

- `src/components/icon/index.tsx`
- `src/components/icon-button/index.tsx`
- `src/components/icon-button/IconButton.types.ts`
- `src/components/tooltip-icon-button/index.tsx`
- `src/components/tooltip-icon-button/TooltipIconButton.types.tsx`

Health: `high risk`.

Confirmed concerns:

- P1-06: Icon's semantic direction is inverted. An undecorated image can expose
  an internal asset key as alternative text, while an injected SVG has no
  complete semantic-name contract;
- decorative status must be explicit and consistent at every call site;
- an icon-only action needs a translated accessible name on the interactive
  control, not an asset name on its child image;
- P2-02: TooltipIconButton uses a generic wrapper as a tooltip trigger, adding
  another interaction/focus boundary instead of decorating the real button;
- duplicate feature-local icon maps remain under P2-06.

Implementation status: `planned`.

### Input and FieldContainer

Files:

- `src/components/input/index.tsx`
- `src/components/field-container/index.tsx`

Health: `critical`.

Confirmed concerns:

- P0-02: token and density values are not fully routed through the shared
  `--auralith-*` contract;
- P0-03: FieldContainer renders visible text rather than a real label bound by
  `for`/`id`;
- error presentation is not a complete `aria-invalid` and
  `aria-describedby` contract;
- clear-search labeling is embedded English rather than translated UI copy;
- ownership of generated IDs, hint IDs, error IDs, required state, and focus
  needs to be defined between FieldContainer and Input.

Implementation status: `not started`.

### Checkbox, RadioButton, and ToggleButton

Files:

- `src/components/checkbox/index.tsx`
- `src/components/radio-button/index.tsx`
- `src/components/toggle-button/index.tsx`

Health: `critical`.

Confirmed concerns:

- P0-02: tokens and density are not yet consistently applied across all three
  controls;
- P1-03: native name, value, form, label, controlled/uncontrolled, focus,
  disabled, and change semantics are incomplete or inconsistent;
- the visual control and the native interactive element must be one logical
  target for mouse, touch, and keyboard users;
- a control must not rely on a surrounding clickable paragraph or feature code
  to implement its native state transition.

Implementation status:

- Checkbox: `implemented and validated for the declared contract`;
- RadioButton: `not started`;
- ToggleButton: `not started`.

Checkbox now forwards native input and accessibility attributes, supports
controlled and uncontrolled state, generates an ID when needed, and exposes a
normal change event. This does not close the RadioButton or ToggleButton work.

### Tabs

Files:

- `src/components/tabs/index.tsx`

Health: `critical` because it participates in P0-02.

Confirmed concerns:

- spacing, control height, color, focus, and density are not fully expressed by
  semantic tokens;
- orientation, activation, disabled state, overflow, and keyboard navigation
  require an explicit public contract;
- active state must remain clear in forced-colors and cannot be color-only.

Implementation status: `not started`.

### DropdownMenu, DropDownItem, and ComboBox

Files:

- `src/components/dropdown/index.tsx`
- `src/components/dropdown/DropDown.types.tsx`
- `src/components/dropdown-item/index.tsx`
- `src/components/dropdown-item/DropDownItem.types.tsx`
- `src/components/combo-box/index.tsx`

Health: `critical`.

Confirmed concerns:

- P0-02: token and density propagation is incomplete;
- P1-02: DropDownItem can nest focusable controls inside a menu item;
- submenu ownership is implemented with a window-level `mousemove` listener,
  estimated geometry, and manually coordinated hover state;
- toggle, about, submenu, checkmark, tooltip, separator, and normal action
  variants are combined in one component without a safe semantic mode;
- keyboard, pointer, dismissal, RTL side selection, and narrow-panel behavior
  must be owned by one menu primitive rather than feature-local event logic.

Implementation status: `not started`.

### Dialog compound components

Files:

- `src/components/dialog/index.tsx`
- `src/components/dialog/sub-components/Dialog.tsx`
- `DialogTrigger.tsx`
- `DialogPortal.tsx`
- `DialogOverlay.tsx`
- `DialogContent.tsx`
- `DialogTitle.tsx`
- `DialogDescription.tsx`
- `DialogFooter.tsx`

Health: `provisional foundation`.

Confirmed concerns:

- the compound structure is reusable, but every consumer must use dialog-owned
  focus, Escape, dismissal, title, description, and submit behavior;
- feature components still add global Enter listeners, bypassing dialog and
  form semantics;
- size variants, scroll behavior, narrow widths, high zoom, and host z-index
  must be typed and tokenized rather than selected with unrelated booleans;
- confirmation dialogs need an explicit destructive/default-action contract.

Implementation status: `planned`.

### Tooltip compound components

Files:

- `src/components/tooltip/index.tsx`
- `src/components/tooltip/sub-components/Provider.tsx`
- `Tooltip.tsx`
- `TooltipTrigger.tsx`
- `TooltipContent.tsx`

Health: `migration required`.

Confirmed concerns:

- P2-02: wrapper triggers can create an unnecessary interaction boundary;
- controlled visibility, disabled-trigger behavior, delay, collision,
  accessible description, and touch behavior need a stable API;
- tooltip content cannot be the only source of an essential accessible name or
  instruction.

Implementation status: `not started`.

### Loader

Files:

- `src/components/loader/index.tsx`

Health: `provisional foundation`.

Confirmed concerns:

- motion must use the shared timing contract and stop under reduced motion;
- callers must supply status text where loading state is meaningful;
- size, color, and inline/block variants need tokenized public props.

Implementation status: `planned`.

### Design-system foundations

Files:

- `src/index.css`
- `src/styles/foundations.css`
- `src/styles/semantic.css`
- `src/styles/components.css`
- `src/styles/themes.css`
- `src/styles/theme-registry.ts`
- the seven `src/styles/theme-*.css` palette files

Health: `critical` because this layer owns the contract required by P0-02.

Confirmed state and concerns:

- shared foundation, semantic, interaction, custom-color, and theme-registry
  layers exist in the working tree;
- many controls and feature styles still consume legacy component variables or
  fixed values, so file presence does not mean the token system is complete;
- theme files must own palettes while shared component mappings remain in one
  layer;
- density, typography, motion, focus, z-index, and host customization must be
  resolved without feature-specific theme branches.

Implementation status: `foundation accepted; cross-component migration
incomplete`.

## Composite-control inventory

### FileItem

Files:

- `src/components/file-item/index.tsx`

Health: `migration required`.

Confirmed concerns:

- icon naming, remove-action labeling, truncation, file identity, and
  long-path behavior need typed slots and translated names;
- attachment rendering must remain valid at narrow widths and high zoom;
- it must not duplicate file-type icon mapping already owned by attachment
  selection.

Implementation status: `planned`.

### Markdown, Shiki, CodeHeader, and copy hook

Files:

- `src/components/markdown/index.tsx`
- `src/components/markdown/Markdown.types.tsx`
- `src/components/markdown/Markdown.utils.tsx`
- `src/components/markdown/sub-components/CodeHeader.tsx`
- `src/components/markdown/hooks/useCopyToClipboard.tsx`
- `src/components/assistant-ui/shiki-highlighter.tsx`

Health: `high risk`.

Confirmed concern P1-08 covers:

- legacy component color variables rather than the semantic token contract;
- incomplete RTL behavior for prose, code, tables, and action placement;
- `_blank` links without one centralized safe-link policy;
- Markdown and the Assistant UI Shiki highlighter can drift in theme and
  language behavior;
- copy success, failure, permission denial, timeout cleanup, and accessible
  announcement need one copy-action primitive.

Implementation status: `not started`.

### ToolFallback

Files:

- `src/components/tool-fallback/index.tsx`

Health: `high risk`.

Confirmed concern P1-04 covers:

- clickable `div` and `span` elements are used for expand, external navigation,
  result selection, and copy;
- the displayed copy state can change without copying the arguments or result;
- keyboard activation, focus, link safety, live status, malformed JSON,
  cancellation, and long-output behavior are not one managed contract;
- this component is also rendered inside permission UX, so presentation must
  remain side-effect free.

Implementation status: `not started`.

### ManageToolDialog

Files:

- `src/components/manage-tool-dialog/index.tsx`

Health: `critical`.

Confirmed concern P0-01:

- a global Enter listener could invoke Allow regardless of whether focus was on
  Deny, Close, or the persistent-permission choice;
- the persistent permission checkbox did not have a reliable native label and
  change path;
- authorization, denial, close, default action, and persistent permission must
  remain distinct host-owned actions.

Implementation status: `implemented and validated for P0-01`.

The implementation removes the global Enter listener, uses a real form submit
for Allow, keeps Deny and Close non-authorizing, and connects a real label to
the Checkbox. Contract tests and the targeted three-case Chromium fixture
verify Deny, Close, Checkbox, and Allow paths. Office write approval remains
production-blocked by the separate capability architecture.

## Agent-shell inventory

### App and Layout shell

Files:

- `src/main.tsx`
- `src/App.tsx`
- `src/components/layout/index.tsx`
- `src/components/layout/sub-components/Header.tsx`
- `ChatList.tsx`
- `ChatListItem.tsx`
- `DeleteChatDialog.tsx`
- `src/components/layout/layout.css`

Health: `migration required`.

Confirmed concerns:

- Layout still coordinates routing, shell state, history, and responsive UI
  across presentational children;
- P2-06: icon maps and action renderings are repeated;
- header, history, selection, rename, download, delete, empty, loading, and
  error states need typed component contracts;
- shell width and mode must be driven by container/host context rather than a
  duplicated sidebar implementation.

Implementation status: `planned`.

### Chat and Composer

Files:

- `src/pages/chat/index.tsx`
- `AssistantMessage.tsx`
- `UserMessage.tsx`
- `Welcome.tsx`
- `Composer.tsx`
- `ComposerAction.tsx`
- `ComposerActionAttachments.tsx`
- `ComposerActionSelectModel.tsx`
- `ComposerActionSend.tsx`
- `ComposerActionServers.tsx`
- `src/pages/chat/Thread.css`

Health: `migration required`.

Confirmed concerns:

- P2-03: the thread maximum width and composer layout are feature-local rather
  than a shared, host-customizable content-width contract;
- P2-04: the composer input accessible name is embedded English instead of
  translated product copy;
- P2-05: recent-files and attachment metadata parsing assumes valid JSON and
  can fail during render;
- P2-06: file-type and action icon maps are duplicated;
- message attachments also parse serialized metadata repeatedly without a
  validated adapter;
- message, composer, attachment, model, server, disabled, streaming, stop, and
  error states require component-level contracts.

Implementation status: `not started`.

### Empty and Settings roots

Files:

- `src/pages/empty-screen/index.tsx`
- `src/pages/settings/index.tsx`
- `src/pages/empty-screen/EmptyScreen.css`
- `src/pages/settings/Settings.css`

Health: `provisional foundation`.

Confirmed concerns:

- these roots are useful page boundaries, but layout, navigation, title,
  focus-restoration, and narrow-width behavior need documented contracts;
- page roots must compose shared controls and cannot create local token or
  keyboard systems.

Implementation status: `planned`.

### Provider settings

Files:

- `src/pages/settings/sub-components/providers/index.tsx`
- `ProviderItem.tsx`
- `AddProviderDialog.tsx`
- `EditProviderDialog.tsx`
- `DeleteProviderDialog.tsx`

Health: `high risk`.

Confirmed concern P1-05:

- Add and Edit duplicate provider form fields, validation, state, and layout;
- global Enter listeners bypass normal form/default-button behavior;
- provider name, URL, secret, validation, submission, cancellation, error, and
  focus restoration need one form controller and shared presentational fields;
- secret values and errors must not leak into visual, console, or test
  evidence.

Implementation status: `not started`.

### Server, tool, web-search, and wallet settings

Files:

- `src/pages/settings/sub-components/servers/index.tsx`
- `AvailableTools.tsx`
- `AvailableToolsItem.tsx`
- `ConfigDialog.tsx`
- `DeleteServerDialog.tsx`
- `LogsDialog.tsx`
- `src/pages/settings/sub-components/web-search/index.tsx`
- `src/pages/settings/sub-components/wallet/index.tsx`

Health: `high risk`.

Confirmed concerns:

- several dialogs add feature-local global keyboard listeners;
- AvailableToolsItem combines status, actions, tooltip, submenu, removal,
  navigation, and reset behavior in one large component;
- JSON configuration parsing, clipboard failure, disabled state, pending state,
  and server error recovery need managed boundaries;
- ManageToolDialog authorization state must not be inferred or implemented by
  these presentation components.

Implementation status: `not started`.

## Reader and model-configuration inventory

### ReaderApp, ReaderHeader, and AuralithMark

Files:

- `src/document-reader/ui/ReaderApp.tsx`
- `src/document-reader/ui/ReaderHeader.tsx`
- `src/document-reader/ui/AuralithMark.tsx`
- `src/document-reader/ui/reader.css`
- `src/reader-main.tsx`

Health: `critical`.

Confirmed concerns:

- P0-04: visible Reader strings are hard-coded in Chinese and are not
  delivered through a real language/catalog bridge;
- P1-01: ReaderApp is approximately 1,368 lines and `reader.css` approximately
  1,568 lines in the reviewed snapshot;
- the component mixes document bridge I/O, model I/O, consent, persistence,
  task state, retrieval, citation navigation, error handling, and rendering;
- state labels, unsupported-editor UI, confirmation, model setup, consent,
  progress, answers, citations, stale state, and errors need extracted
  presentational components;
- CSS owns many feature states and breakpoints without a component-scoped
  variant map.

Implementation status: `not started`.

ReaderApp MUST be split by ownership without changing document semantics:

1. a controller owns the Reader state machine and async orchestration;
2. adapters own host, document, model, storage, and consent I/O;
3. presentational components receive typed state and callbacks;
4. translations enter through the same locale bridge as the Agent shell;
5. ReaderHeader and AuralithMark remain small presentational primitives.

### LlmSettingsApp and AgentModelConfiguration

Files:

- `src/model-config/LlmSettingsApp.tsx`
- `src/model-config/AgentModelConfiguration.tsx`
- `src/model-config/harness-target.ts`
- `src/model-config/model-capabilities.ts`
- `src/model-config/model-selection.ts`
- `src/model-config/provider-reference.ts`

Health: `critical`.

Confirmed concerns:

- P0-04: labels, notices, errors, capability states, help text, consent text,
  and accessible names are hard-coded in Chinese;
- receiving a locale or theme message from the host is not equivalent to
  translating the rendered view through a catalog;
- model selection, provider management, capability declaration, capability
  probing, remote consent, local-model consent, and notices are coordinated
  across large components;
- presentational controls must consume typed data and callbacks rather than
  read provider/store/host state directly.

Implementation status: `not started`.

## web-apps host inventory

Files:

- `web-apps/apps/common/main/lib/auralith-agent-host.js`
- `web-apps/apps/common/main/lib/auralith-agent-host.css`
- Auralith script/style insertion points in document, spreadsheet,
  presentation, PDF, and diagram editor `main/index.html` files.

Health: `high risk`.

Confirmed concern P1-07:

- the host JavaScript is now greater than one thousand lines and owns a large
  imperative DOM/MutationObserver overlay;
- launcher insertion, iframe creation, width, theme, locale, settings,
  capability checks, document bridge, message transport, and cleanup are
  concentrated in one file;
- DOM discovery through observers is sensitive to upstream layout and lifecycle
  changes;
- the fixed overlay is not yet a stable layout-aware editor slot;
- the host needs explicit mount, update, unmount, focus, docking, resize,
  capability, theme, locale, and failure contracts.

Implementation status: `not started`.

The host may own editor integration and authority, but it MUST NOT duplicate
Reader or Agent feature UI. New host behavior should be split into pure
configuration/capability logic, bridge adapters, and a small view/mount layer.

## Harness and Office-adapter inventory

These families are included because component availability and side effects
cannot be safely managed if the UI probes globals or invents its own tool
contract.

### General Agent Harness

Files and owned families:

- `src/agent-harness/contracts.ts`
- `errors.ts`
- `format-profiles.ts`
- `harness.ts`
- `prompt-selector.ts`
- `registry.ts`
- `tool-registry.ts`
- `validation.ts`
- `index.ts`

Health: `adapter foundation`.

Confirmed state:

- typed session, task, tool, validation, error, and policy foundations exist;
- UI capability availability still needs one canonical registry and context;
- presentation components must not self-register, self-approve, or directly
  execute tools;
- formatting is not a production-ready Harness path and must remain reported
  as blocked in `AURALITH_AI_NATIVE_ARCHITECTURE.md`.

Implementation status: `canonical registry and context-epoch foundation
validated; generic chat routing and the production write executor remain open`.

### Office capability adapters

Files and owned families:

- `src/office-tools/office-capability-registry.ts`
- `src/office-tools/selection-text-formatting.ts`
- their contract-oriented test files;
- the corresponding SDKJS semantic methods and web-apps bridge exposure.

Health: `adapter foundation`.

Confirmed state:

- selection-formatting inspection and application have typed and semantic
  foundations;
- the production bridge, host-owned approval, production registration,
  installed-path evidence, and complete manifest lifecycle remain incomplete;
- component availability must come from a typed capability context rather than
  checking SDKJS or host globals in a button or dialog.

Implementation status: `registry, descriptor, and manifest projection
validated; selection formatting remains production-blocked`.

### Reader, model, and host adapters

Files and owned families:

- `src/document-reader/integration/document-bridge.ts`;
- `builtin-document-rpc`, `manifest-adapter`, `incremental-cache`,
  `object-evidence`, `vision-coverage`, and `embedding-adapter`;
- `reader-agent-harness`, `reader-model-service`, and `reader-db`;
- `remote-consent` and `local-model-consent`;
- `src/document-reader/ui/host-bridge.ts`;
- model-configuration target, capability, selection, and provider-reference
  adapters;
- provider adapters under `src/providers`, server adapters under `src/servers`,
  and shared state under `src/store`.

Health: `adapter foundation`.

Confirmed concerns:

- these adapters provide useful seams, but ReaderApp and model settings still
  coordinate too many of them directly;
- host, storage, provider, server, network, and SDKJS access must remain outside
  presentational components;
- adapter results need typed loading, unsupported, stale, consent-required,
  partial, error, and cancellation states;
- duplicated host method inventories must eventually be generated or verified
  from a canonical capability contract.

Implementation status: `host-context unit and registry-parity paths validated;
selection, lock-state, and current full-host browser recertification remain
open`.

## Confirmed priority ledger

Only the explicitly accepted, scoped rows below are closed. Broader
component-family issues remain open until their own closure evidence is
accepted.

### P0: release blockers

| ID | Confirmed issue | Primary owners | Required closure evidence | Implementation status |
| --- | --- | --- | --- | --- |
| P0-01 | ManageToolDialog global Enter authorization race | ManageToolDialog, Dialog, Button, Checkbox, host approval executor | Focused Deny and Close cannot Allow; normal form submit is the only keyboard default; persistent permission is a labeled native choice; approval payload remains immutable | accepted for the UI authorization race; Office writes remain blocked |
| P0-02 | `--auralith-*` token and density contract does not reach Button, Input, Toggle, Checkbox, Radio, Tabs, and Dropdown consistently | Foundation controls and shared style layers | Each state resolves through semantic/foundation tokens across supported themes, density, host override, forced colors, and reduced motion | Button and Checkbox scope accepted; remainder not started |
| P0-03 | FieldContainer/Input lack a complete label, `for`, `aria-invalid`, and `aria-describedby` contract | FieldContainer and Input | Bound label and generated IDs; hint/error description; required/invalid state; keyboard and screen-reader contract | not started |
| P0-04 | Reader and model configuration hard-code Chinese; the language bridge does not truly localize the view | ReaderApp, LlmSettingsApp, AgentModelConfiguration, host locale bridge | Catalog-backed Chinese, English, and RTL rendering; runtime locale update; translated accessible names/errors/status; no feature strings embedded in components | not started |

### P1: structural and semantic risks

| ID | Confirmed issue | Primary owners | Required closure evidence | Implementation status |
| --- | --- | --- | --- | --- |
| P1-01 | ReaderApp and reader.css mix controller, I/O, state machine, and presentation at approximately 1,368/1,568 lines | Reader UI/controller/adapters | Extracted typed state, adapter, and presentational boundaries with equivalent workflow behavior | not started |
| P1-02 | DropDownItem nests focusable controls and manually coordinates submenu `mousemove`/geometry | Dropdown family | One menu semantic model for action, check, toggle, about, and submenu variants; keyboard, pointer, RTL, collision, and dismissal evidence | not started |
| P1-03 | Toggle, Checkbox, and Radio native semantics are incomplete | Selection-control family | Native form/name/value/label/focus/disabled/change contract, controlled and uncontrolled where supported | Checkbox scope accepted; Toggle and Radio not started |
| P1-04 | ToolFallback uses clickable `div`/`span`; copy feedback does not perform the copy | ToolFallback and shared action/copy primitives | Real button/link controls; actual clipboard operation and failure state; keyboard, safe-link, long-output, and malformed-result behavior | not started |
| P1-05 | Provider Add/Edit forms duplicate logic and use global Enter behavior | Provider settings and Dialog | One provider form controller/schema; semantic submit/cancel; secret-safe errors; focus restoration | not started |
| P1-06 | Icon semantic direction is wrong | Icon and all icon call sites | Decorative icons hidden; meaningful graphics have product-facing names; interactive names live on controls; no asset-key alt text | not started |
| P1-07 | web-apps host is a greater-than-one-thousand-line imperative DOM/MutationObserver overlay | web-apps host | Stable editor slots/lifecycle; split mount, bridge, capability, and configuration modules; resize/theme/locale/focus failure evidence | not started |
| P1-08 | Markdown token, RTL, `_blank`, and Shiki behavior can drift | Markdown, CodeHeader, copy hook, Shiki adapter | Semantic tokens, safe link policy, shared highlighter theme mapping, RTL/code/table behavior, actual copy with failure state | not started |

### P2: maintainability debt

| ID | Confirmed issue | Primary owners | Required closure evidence | Implementation status |
| --- | --- | --- | --- | --- |
| P2-01 | Button `scale` and default `type` behavior are not a safe public contract | Button | Typed variant consumption; no invalid DOM prop; safe native default; explicit submit and `asChild` behavior | accepted |
| P2-02 | Tooltip wrapper trigger adds an unnecessary semantic/focus boundary | TooltipIconButton and TooltipTrigger | Tooltip decorates the real trigger; ref, disabled, pointer, focus, and accessible-description behavior | not started |
| P2-03 | Chat maximum width is feature-local and rigid | Chat, messages, composer, Thread.css | Shared content-width token; narrow, docked, start-page, high-zoom, and host override behavior | not started |
| P2-04 | Composer accessible name is embedded English | Composer | Translated accessible name from the shared catalog and runtime locale update | not started |
| P2-05 | Recent-file and attachment `JSON.parse` occurs without a defensive validated adapter | ComposerActionAttachments and UserMessage | Parse/shape failure is contained and shown as a recoverable state; render cannot crash | not started |
| P2-06 | File/action icon maps are repeated | Attachment, FileItem, history, provider/server actions | One typed semantic icon registry or explicit component slots without feature-local copies | not started |

## Component governance target

Every Auralith reusable component MUST have:

- one named owner and one public import path;
- typed props with stable semantic variants;
- a declared presentational, controller, or adapter role;
- controlled state when an external workflow owns the decision;
- native semantics and translated accessible names;
- loading, disabled, empty, error, long-content, and cancellation behavior where
  applicable;
- documented slots or composition points instead of copied markup;
- `--auralith-*` semantic/foundation tokens for color, typography, spacing,
  radius, z-index, density, and motion;
- logical layout properties and verified RTL behavior;
- focus ownership, keyboard behavior, dismissal, and focus restoration;
- a component-level DOM contract and representative visual states;
- no direct SDKJS, host-global, storage, provider, or network access from a
  presentational component.

Breaking prop changes require a migration in the same change. A new feature
variant extends the shared typed API or introduces a new semantic component; it
does not copy markup and CSS into a feature folder.

## Implementation order

### 0. Preserve the audit boundary

1. Keep this inventory current when Auralith adds or modifies a component.
2. Assign every changed component a health and implementation status.
3. Reject generated deploy output, vendored code, and untouched upstream code
   as false component-count inflation.
4. Treat a newly modified upstream seam as in scope.

Exit condition: no Auralith-owned UI or integration seam is unowned.

### 1. Close P0 authorization and foundation contracts

1. Validate the ManageToolDialog, Button, and Checkbox candidates without
   prematurely marking them complete.
2. Finish semantic token and density migration for Input, Toggle, Radio, Tabs,
   Dropdown, ComboBox, and all interaction states.
3. Implement the FieldContainer/Input label, ID, hint, error, required, and
   invalid contract.
4. Move Reader and model-configuration strings, status, errors, consent, and
   accessible names into the shared locale catalog and runtime bridge.

Exit condition: all P0 rows have accepted implementation and validation
evidence, and the final integrator has updated their status.

### 2. Repair native semantics and unsafe interaction composition

1. Replace DropdownItem's multi-mode nested interaction model.
2. Complete Toggle/Radio semantics and revalidate Checkbox as a family.
3. Replace ToolFallback clickable containers with buttons/links and implement
   real copy behavior.
4. Consolidate provider Add/Edit into one form controller and remove global
   Enter handlers from feature dialogs.
5. Correct Icon's decorative/meaningful contract and Tooltip's trigger
   composition.

Exit condition: keyboard and assistive-technology behavior follows native
semantics without global feature key handlers.

### 3. Split large controllers and host integration

1. Separate Reader controller, adapters, and presentational state components.
2. Divide `reader.css` into foundation mappings and component-scoped styles.
3. Split the web-apps host into lifecycle/mount, capability, bridge, and
   configuration modules.
4. Replace the observer-dependent fixed overlay with stable editor slots and a
   layout-aware panel contract.

Exit condition: presentation can be rendered with typed fixture state and
without real host, storage, provider, network, or SDKJS globals.

### 4. Resolve P2 and remove duplication

1. Centralize chat/content width.
2. Translate Composer's accessible name.
3. Add defensive recent-file and attachment adapters.
4. Consolidate semantic icon mappings.
5. Finish safe Tooltip, Markdown, Shiki, copy, link, and RTL behavior.

Exit condition: feature code composes shared contracts rather than maintaining
local forks.

### 5. Enforce governance

Add gates for:

- TSX DOM-contract tests and component coverage;
- keyboard and focus behavior;
- automated accessibility checks;
- computed tokens and host custom overrides;
- white, gray, night, and contrast-dark themes;
- 420px, 370px, 320px, and 280px widths plus high zoom;
- Chinese, English, and an RTL locale;
- reduced motion and forced colors;
- empty, setup, loading, ready, warning, error, long-content, stale, and
  cancellation states;
- failure on unallowlisted browser `pageerror` and console errors;
- production-bundle and real-host fixtures where integration is involved.

Use Node.js 20 for Agent validation. Build with `npx vite build`; do not use the
legacy root build command that overwrites tracked deploy assets.

## Final implementation-status update

| Field | Required final value |
| --- | --- |
| Implementation status | Audit complete; first scoped remediation accepted; release blockers remain. |
| Accepted P0 IDs | P0-01 for the UI authorization race; partial P0-02 for Button and Checkbox only. |
| Accepted P1 IDs | Partial P1-03 for Checkbox only. |
| Accepted P2 IDs | P2-01. |
| Deferred IDs with owner and milestone | All other rows remain assigned to their listed owners and the ordered roadmap above. |
| Validation commands and exact scope | Node 20 Reader typecheck; 71 files / 1,022 Vitest tests; 3 targeted Chromium approval tests; focused Biome; Vite production build; diff checks; 280 px and 400 px in-app visual inspection; isolated installed-bundle hash, signature, and process checks. |
| Known unsupported surfaces | Production selection formatting; Spreadsheet, Presentation, PDF, and Diagram semantic adapters; native GUI click-through while macOS is locked; current full-browser-suite recertification. |
| desktop-sdk commit | Working-tree changes are uncommitted. |
| web-apps commit | Working-tree changes are uncommitted. |

The correct project statement is:

> The Auralith-owned component boundary has been audited. The scoped
> ManageToolDialog, Button, and Checkbox remediations are accepted, the
> read-only AI-native registry and host-context foundation is validated, and
> the remaining component-family and Office-write work stays explicitly open.
