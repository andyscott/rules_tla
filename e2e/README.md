# End-to-end tests

This directory is a standalone Bazel module, following the same general pattern used by
`rules_py`.

Run the external-consumer smoke coverage from this directory:

```bash
bazel test //...
bazel test //... --experimental_output_paths=strip
```

The cases currently cover:

- happy-path Bzlmod consumption of `tla_library`, `pluscal_library`, and `tlc_test`
- happy-path Bzlmod consumption of `apalache_check`
- happy-path Bzlmod consumption of `apalache_simulate`

The negative PlusCal case is checked in alongside the smoke suite and is meant to be
invoked explicitly:

```bash
bazel build //negative_pluscal:bad_spec_under_test
```
