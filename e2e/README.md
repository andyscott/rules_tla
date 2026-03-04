# End-to-end tests

This directory is a standalone Bazel module, following the same general pattern used by
`rules_py`.

Run the external-consumer smoke coverage from this directory:

```bash
./bazelw test //...
./bazelw test //... --experimental_output_paths=strip
```

On macOS, `./bazelw` prefers the Command Line Tools developer directory when it is
present, so Rust toolchain bootstrap does not require the full Xcode app to be active.

The cases currently cover:

- happy-path Bzlmod consumption of `tla_library`, `pluscal_library`, and `tlc_test`
- happy-path Bzlmod consumption of `apalache_check`
- happy-path Bzlmod consumption of `apalache_simulate`
- happy-path Rust integration with `tla-connect`, `rules_rust`, `rules_rs`, and an explicit `apalache_generate_traces` -> `rust_test` replay flow

The negative PlusCal case is checked in alongside the smoke suite and is meant to be
invoked explicitly:

```bash
bazel build //negative_pluscal:bad_spec_under_test
```
