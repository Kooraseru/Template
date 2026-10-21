# Implementation workflow

1. Identify the owner and contract of each changed behavior.
2. Make the smallest cohesive change, without introducing a parallel command route.
3. Run focused checks and the applicable GitHub Actions jobs.
4. Preserve staged security and publication gates.
5. Record deferred migrations explicitly; do not claim an unfinished refactor is complete.
