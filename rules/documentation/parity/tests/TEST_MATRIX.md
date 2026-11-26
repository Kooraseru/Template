# Test matrix

| Fixture | Expected |
|---|---|
| valid/matching | No discrepancies |
| valid/tolerance | One CSS pixel permitted |
| invalid/geometry | Geometry mismatch |
| invalid/color | Color mismatch |
| invalid/font | Typography mismatch |
| invalid/state | State mismatch |
| invalid/text | Content mismatch |
| review/missing | Infrastructure failure, never pass |

Run `node dependencies/packages/checks/testSuites/run.cjs documentation-parity`.
