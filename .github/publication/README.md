# Publication Configuration

Generated branches are built from the explicit whitelist in `config.yml`.
Publication is disabled until an adopting project sets `enabled: true` and
declares non-empty `include` and `required` lists.

Every path is relative to the repository root. Entries must not be absolute,
contain `..`, resolve through symlinks outside the repository, overlap `.git`,
or include private local knowledge. Required entries must also be included by
the payload.

The builder creates `.github/publication.json` with the selected channel,
version, immutable source commit, and generation time. It writes only beneath
`.generated/repo/<channel>/`.
