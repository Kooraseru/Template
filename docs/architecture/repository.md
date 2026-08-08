# Repository Architecture

The repository separates authored source, human documentation, GitHub
automation, and generated output.

```text
source
├── SOURCE.md
├── docs/                 human rules and documentation
├── src/ and tests/       project-owned implementation surfaces
├── .github/              contributor policy and GitHub automation
└── .generated/           ignored local output
    ├── site/             MkDocs output
    └── repo/<channel>/   publication payloads
```

The `source` branch is canonical. Automation derives `pre-release` and
`release` from one immutable source commit and records that commit in the
generated publication manifest.

Projects may add source domains as they adopt the template. Each durable domain
should have one clear owner in source or documentation; avoid duplicated
contracts and hand-maintained registries.
