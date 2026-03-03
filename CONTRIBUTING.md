# Contributing

## Scope

`pkg-maint` is intentionally small and conservative. Contributions should keep the tool:

- shell-based
- easy to audit
- focused on global package maintenance

## Workflow

1. Fork the repo or create a feature branch.
2. Make your changes in small, reviewable commits.
3. Run the regression suite:

```sh
make test
```

4. Update documentation when behavior changes.
5. Open a pull request with a concise description of:
   - the problem
   - the change
   - how it was tested

## Style

- Prefer POSIX shell in `bin/pkg-maint`
- Keep dependencies minimal
- Avoid adding complex frameworks or heavy tooling
- Preserve current CLI behavior unless a change is deliberate and documented

## Release Notes

User-facing changes should also update:

- `README.md`
- `CHANGELOG.md`
- `man/pkg-maint.1` when CLI/config behavior changes
