#!/usr/bin/env python3
"""Deterministic nec2c-shaped process used only to regression-test adapter plumbing."""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    output: Path | None = None
    args = sys.argv[1:]
    if len(args) >= 2 and not args[0].startswith("-"):
        output = Path(args[1])
    for i, arg in enumerate(args):
        if arg == "-o" and i + 1 < len(args):
            output = Path(args[i + 1])
        elif arg.startswith("-o") and len(arg) > 2:
            output = Path(arg[2:])
    if output is None:
        print("fake-nec2c requires positional input/output, -o <path>, or -o<path>", file=sys.stderr)
        return 2
    output.write_text(
        """                              - - - - - - FREQUENCY - - - - - -
                              FREQUENCY= 2.99792458E+02 MHZ

                              - - - ANTENNA INPUT PARAMETERS - - -
 TAG SEG. VOLTAGE (VOLTS) CURRENT (AMPS) IMPEDANCE (OHMS) ADMITTANCE (MHOS) POWER
 NO. NO. REAL IMAG. REAL IMAG. REAL IMAG. REAL IMAG. (WATTS)
 1 26 1.00000E+00 0.00000E+00 9.10000E-03 -5.00000E-03 8.47500E+01 4.67000E+01 0.00000E+00 0.00000E+00 4.50000E-03
""",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
