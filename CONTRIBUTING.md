# Contributing

Thanks for improving `shell-up.sh`.

## Local Checks

Run syntax checks before opening a pull request:

```bash
bash -n shell-up.sh
```

Preview behavior without changing your system:

```bash
./shell-up.sh --dry-run 11
./shell-up.sh --dry-run --yes 7 8
```

## Guidelines

- Keep the script readable and dependency-light.
- Prefer idempotent changes.
- Keep `.zshrc` edits inside managed shell-up blocks when possible.
- Use `--dry-run` friendly behavior for new installation paths.
- Avoid destructive commands.
