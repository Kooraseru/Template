# Implementation workflow

1. Identify the authoritative owner and contract of each behavior being changed.
2. Make the smallest cohesive change without introducing a parallel command or policy route.
3. Discover optional components from their owning directories and validate their shapes; do not update hardcoded inventories to make additions work.
4. Run relevant static checks, preflight, and supported integration or platform execution, according to the change.
5. Preserve security, provenance, and publication gates.
6. Record deferred migrations explicitly. Do not report an unfinished refactor, skipped branch, or unavailable platform as verified.
