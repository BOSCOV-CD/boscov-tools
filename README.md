# BOSCOV Tools

Free performance tools for Windows & BlueStacks, built by **BOSCOV**.

## BOSCOV Boost v1.0
RAM / startup / background / telemetry booster for Windows 10 & 11.

- Auto-elevates to Administrator (UAC prompt)
- Backs up every value it changes
- Undo everything with one command:
  ```
  powershell -File "BOSCOV Boost.ps1" -Revert
  ```

## BOSCOV Optimizer v1.0
BlueStacks 5 FPS & smoothness optimizer for Windows 10 & 11.

- Auto-elevates to Administrator (UAC prompt)
- Backs up every file/registry value it changes
- Undo everything with one command:
  ```
  powershell -File "BOSCOV Optimizer.ps1" -Revert
  ```

## How to run
1. Download the `.ps1` file
2. Right-click it -> **Run with PowerShell** (or run `powershell -ExecutionPolicy Bypass -File "BOSCOV Boost.ps1"`)
3. Approve the UAC prompt - done

## Safety
- 100% local: no telemetry, no data collection, no network calls
- Every change is backed up and reversible
- Free to share
