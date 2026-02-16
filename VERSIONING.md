# Versioning Policy (PhobosLib)

PhobosLib is a dependency library. Treat versions as API contracts.

## Scheme
Use Semantic Versioning: **MAJOR.MINOR.PATCH**

- **MAJOR**: breaking API changes
  - removing/renaming public functions or modules
  - changing argument order/types or return types
  - changing documented behavior in a way that breaks callers
- **MINOR**: backward-compatible additions
  - new helper functions
  - new optional parameters with safe defaults
  - performance improvements that keep behavior
- **PATCH**: backward-compatible bug fixes
  - crash fixes, nil guards, pcall wrappers
  - documentation corrections
  - internal refactors that do not change behavior

## What counts as “public API”
Assume public unless explicitly marked private:
- documented functions in README/docs
- any function used by downstream mods
- module/table names exposed for require()

If a helper is experimental, mark it clearly in docs as **EXPERIMENTAL**.

## Deprecation (recommended)
If you need to replace an API:
1) keep the old API for at least one MINOR release
2) add a deprecation note in CHANGELOG.md
3) optionally print a one-time warning (avoid spam)
4) remove in the next MAJOR release

## Tagging releases
- Tag GitHub releases as `vX.Y.Z`
- Include a concise changelog section for each release
