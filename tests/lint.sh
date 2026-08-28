#!/usr/bin/env bash
cd "$(dirname "$0")/.."
python3 tests/lint.py --selftest || exit 1
python3 tests/lint.py
