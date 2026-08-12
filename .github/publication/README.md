# Publication Configuration

Generated branches are built from the explicit whitelist in `config.yml`.
Publication is disabled until an adopting project sets `enabled: true` and
declares non-empty `include` and `required` lists.

Every path is relative to the repository root. Entries must not be absolute,
contain `..`, resolve through symlinks outside the repository, overlap `.git`,
or include private local knowledge. Required entries must also be included by
the payload.

The builder creates `.github/publication.json` with the selected channel,
release ID, immutable source commit, and generation time. Release IDs use
`YYYY.MM.N-KIND`; the channel remains a separate publication destination. The
whitelist includes `src/` as user-downloadable project source. The builder
writes only beneath `.generated/repo/<channel>/`.
