# Auralith_Editer agent instructions

On macOS or in a fresh clone, read `MACOS_HANDOFF.md` before changing code.
If `desktop-sdk`, `web-apps`, or `sdkjs` is missing or not on the expected
commit, run:

```bash
bash tools/bootstrap-auralith-macos.sh
```

The three modified components are standard Git submodules hosted in the
`Yecyi` forks. Keep their `origin` remotes on the `Yecyi` repositories and
their `upstream` remotes on `ONLYOFFICE`. Never commit a root gitlink that
cannot be fetched from the configured fork.

Commit and push changes inside a submodule first. Then commit the updated
gitlink in `Auralith_Editer`.

Use Node.js 20 for AI Agent tests. Validate builds with `npx vite build`; do
not use the legacy root build command that overwrites tracked deploy assets.
Product naming in new UI and documentation is `Auralith_Editer` and
`Auralith Agent`.
