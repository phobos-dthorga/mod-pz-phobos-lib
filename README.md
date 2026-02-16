# PhobosLib

A shared utility library for Project Zomboid mods (Build 42 focused).

## Goals
- Provide stable, reusable helpers (sandbox vars, API probing, world scan, fluid helpers, etc.)
- Reduce duplicated Lua glue code across mods
- Improve resilience to minor B42 API changes through safe wrappers

## Intended usage
- As a dependency: your mod can require PhobosLib and call its helpers.
- As a vendored snippet source: small snippets may be copied with attribution, but depending on the library is preferred.

## Stability promise
Public functions in PhobosLib should be treated as API surface. Changes should:
- avoid breaking signatures
- remain backwards compatible where possible
- include migration notes when breaking changes are unavoidable

## Files to read
- LICENSE
- PROJECT_IDENTITY.md
- MODDING_PERMISSION.md
- CONTRIBUTING.md

## Release notes
- See CHANGELOG.md
- See VERSIONING.md
