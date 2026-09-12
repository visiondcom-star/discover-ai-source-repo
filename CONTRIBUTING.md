# Contributing Guide

Thank you for contributing! Here are the key git guidelines:

## Safety Rules

### 🔐 Git Safety Rules
- **Never** use `git push --force` or `--force-with-lease` on `main` or any protected branch.
- Always run `git pull` before starting work.
- Never reinitialize with `git init` if the project already exists.

### 💬 Commit Hygiene
- Each commit must represent **one logical change**.
- Write clear messages explaining the **why**, not just the what.

Example:
```bash
git commit -m "Fix login redirect loop after session timeout"
```
Instead of:
```bash
git commit -m "Update auth logic"
```