# Test suites

Every direct directory under `tests/` is a suite and must have a `suite.json`. The directory name is its ID. Keep fixtures and helpers inside their suite.

```json
{
  "version": 1,
  "checks": {
    "example": {
      "runtime": "node",
      "entry": "example.test.cjs",
      "timeoutSeconds": 60
    }
  }
}
```

Use `node` for JavaScript or TypeScript checks and `bash` for shell entry points that launch another runtime, such as Roblox Studio. Entry paths are relative to their suite. Commands run from the repository root. Optional `args` supplies positional arguments. Use `optIn: true` for checks that need a host or credentials, and put timing cases under the optional `benchmarks` object. Write generated output under `build/`.

Run `node dependencies/packages/checks/testSuites/run.cjs` for all default checks. Append a suite name, then a case name if you want just one case. Add `--benchmark` to select the benchmark cases. Set `TEST_SUITE_BASH` to the Bash executable if your shell is installed outside PATH.

CI calls the same runner for default checks. Tests beside shared tooling run explicitly in the native CI workflow.
