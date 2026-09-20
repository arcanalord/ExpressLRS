# EMMana-Next Portable Windows

## For the user

1. Extract the versioned Windows ZIP.
2. Double-click `EMMana-Next.exe`.
3. The program starts locally and opens the default browser.
4. Closing the launcher process stops the local application.

No system Python installation is required.

## Package contents

- `EMMana-Next.exe` — self-contained launcher with Python runtime, UI resources and bundled solver.
- `emnext-cli.exe` — direct solver CLI for diagnostics/engineering use.
- `VERSION`.
- `README-WINDOWS.txt`.

## Security / networking

The launcher binds to `127.0.0.1` by default. It does not expose the UI to the LAN.

## Verification

Windows CI launches the packaged EXE with `--no-browser`, waits for `/api/health`, checks the exact version and confirms that Geometry and Template controls are served.
