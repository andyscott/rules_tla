# `rules_tla`

`rules_tla` provides Bazel rules for validating TLA+ modules with SANY, translating
PlusCal modules, and running TLC from Bazel.

Current shape:

- Bzlmod only
- Bazel 9 oriented
- `BUILD.bazel` naming
- separate rules for plain TLA and PlusCal
- build actions support path mapping via `--experimental_output_paths=strip`

## Installation

Add the module to `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_tla", version = "<pinned version>")
```

When developing against a local checkout, use `local_path_override` instead:

```starlark
bazel_dep(name = "rules_tla", version = "0.0.0")
local_path_override(
    module_name = "rules_tla",
    path = "/absolute/path/to/rules_tla",
)
```

Load the rules from `@rules_tla//tla:tla.bzl`.

## Rule Overview

### `tla_library`

Use `tla_library` for plain `.tla` modules that are already valid TLA+.

```starlark
load("@rules_tla//tla:tla.bzl", "tla_library")

tla_library(
    name = "helper",
    srcs = ["CounterHelper.tla"],
    visibility = ["//visibility:public"],
)
```

Behavior:

- validates direct modules with SANY
- propagates transitive module graphs through `deps`
- does not run PlusCal translation

### `pluscal_library`

Use `pluscal_library` for `.tla` files that contain a PlusCal algorithm.

```starlark
load("@rules_tla//tla:tla.bzl", "pluscal_library")

pluscal_library(
    name = "spec",
    srcs = ["Demo.tla"],
)
```

Behavior:

- runs `pcal.trans`
- validates the translated modules with SANY
- fails if the source file does not contain a PlusCal algorithm
- exposes the translated `.tla` modules to downstream `deps`

### `tlc_test`

Use `tlc_test` for real model checking in CI. This is the main rule for correctness checks.

```starlark
load("@rules_tla//tla:tla.bzl", "tlc_test")

tlc_test(
    name = "model_check",
    cfg = "demo.cfg",
    main_module = "CounterSpec",
    spec = ":spec",
)
```

Behavior:

- requires `main_module` explicitly
- stages the full transitive module graph into TLC
- fails the Bazel test on TLC errors

### `apalache_check`

Use `apalache_check` for bounded symbolic checking with Apalache.

```starlark
load("@rules_tla//tla:tla.bzl", "apalache_check")

apalache_check(
    name = "bounded_check",
    invs = ["Inv"],
    length = 5,
    main_module = "Counter",
    spec = ":spec",
)
```

Behavior:

- runs `apalache-mc check`
- stages the full transitive module graph into an isolated work directory
- uses Bazel's Java runtime toolchain to invoke the packaged Apalache jar
- fails the Bazel test on invariant violations or Apalache/tool errors

Notes:

- Apalache is complementary to TLC, not a replacement for it
- Apalache requires typed specs; variable annotations are often needed
- `apalache_check` accepts invariants in `invs`, temporal properties in `temporals`, or both
- bounded checks still require at least one property to check
- the rule surface supports bounded checks with explicit `length` and optional `cinit` / TLC-style `cfg`

### `apalache_generate_traces`

Use `apalache_generate_traces` when you want Apalache to run as a build action and
materialize a replayable ITF trace corpus for downstream consumers.

```starlark
load("@rules_tla//tla:tla.bzl", "apalache_generate_traces")

apalache_generate_traces(
    name = "counter_traces",
    inv = "TraceComplete",
    length = 6,
    main_module = "CounterModel",
    max_traces = 1,
    spec = ":spec",
)
```

Behavior:

- runs `apalache-mc check` or `apalache-mc simulate` as a normal build action
- stages the transitive module graph into an isolated work directory
- normalizes generated `.itf.json` traces into a declared output directory
- emits a single JSON corpus file for downstream tests that want a stable file artifact
- caches trace generation separately from downstream tests

For Rust replay tests, the intended composition is:

1. create the trace target with `apalache_generate_traces`
2. optionally create a tiny support crate from `@rules_tla//tla/rust:trace_corpus_support.rs`
3. pass that target into an ordinary `rust_test` through `data`
4. use `$(rootpath :your_trace_target)` to point the test at the emitted corpus file

That keeps Apalache execution separate in the Bazel graph while the Rust test stays a normal test target.

For Rust + `tla-connect`, keep the BUILD graph explicit. A minimal pattern looks like:

```starlark
load("@rules_rs//rs:rust_library.bzl", "rust_library")
load("@rules_rs//rs:rust_test.bzl", "rust_test")
load("@rules_tla//tla:tla.bzl", "apalache_generate_traces")

apalache_generate_traces(
    name = "counter_traces",
    inv = "TraceComplete",
    length = 6,
    main_module = "CounterModel",
    spec = ":counter_model",
)

rust_library(
    name = "trace_corpus_support",
    srcs = ["@rules_tla//tla/rust:trace_corpus_support.rs"],
    crate_name = "trace_corpus_support",
    edition = "2021",
    deps = _CRATE_DEPS,
)

rust_test(
    name = "counter_replay_test",
    srcs = ["tests/replay.rs"],
    crate_name = "counter_replay_test",
    data = [":counter_traces"],
    env = {
        "TLA_TRACE_CORPUS": "$(rootpath :counter_traces)",
    },
    deps = _CRATE_DEPS + [
        ":counter_impl",
        ":trace_corpus_support",
    ],
)
```

That keeps the formal work separate and cached while the Rust side stays a normal test target.

### `apalache_simulate`

Use `apalache_simulate` for manual or exploratory Apalache simulation.

```starlark
load("@rules_tla//tla:tla.bzl", "apalache_simulate")

apalache_simulate(
    name = "simulation",
    length = 5,
    main_module = "Counter",
    max_runs = 2,
    spec = ":spec",
    tags = ["manual"],
)
```

Behavior:

- runs `apalache-mc simulate`
- stages the full transitive module graph into an isolated work directory
- writes Apalache logs and artifacts into the test's undeclared outputs directory
- fails the Bazel test on Apalache or spec errors

Notes:

- `apalache_simulate` is for bounded exploration, not merge-blocking correctness checks
- `max_runs` controls how many simulation runs Apalache produces
- `invs`, `temporals`, `cinit`, and `cfg` are available when you want to constrain or inspect the run

### `tlc_simulation`

Use `tlc_simulation` for manual or exploratory TLC simulation.

```starlark
load("@rules_tla//tla:tla.bzl", "tlc_simulation")

tlc_simulation(
    name = "simulation",
    cfg = "demo.cfg",
    main_module = "Demo",
    max_depth = 3,
    max_traces = 1,
    spec = ":spec",
    tags = ["manual"],
)
```

This is intentionally not the main CI surface. Bazel still fails the build if TLC exits
nonzero. Prefer `tlc_test` for merge-blocking checks because simulation is nondeterministic
and weaker than full model checking.

`tlc_simulation` runs bounded random simulation. By default it generates a single trace up to
depth `100`. Increase `max_traces` or `max_depth` when you want a broader manual exploration.

## Module Graphs

Specs can depend on other module libraries through `deps`. The main module is resolved by
module name, not by source ordering.

```starlark
load("@rules_tla//tla:tla.bzl", "tla_library", "tlc_test")

tla_library(
    name = "spec",
    srcs = ["CounterSpec.tla"],
    deps = ["//lib:helper"],
)

tlc_test(
    name = "model_check",
    cfg = "demo.cfg",
    main_module = "CounterSpec",
    spec = ":spec",
)
```

Notes:

- `main_module` may be passed with or without the `.tla` suffix
- duplicate module names in the transitive graph are rejected
- `cfg` must be a `.cfg` file

## Examples

The repo includes examples for the supported shapes:

- `examples/plain_module`: plain TLA module validation
- `examples/hello_world`: PlusCal translation plus TLC test
- `examples/module_graph`: cross-package module graph plus TLC test
- `examples/apalache_counter`: bounded symbolic checking, temporal properties, and simulation with Apalache
- `examples/simple_bank_transfer`: manual TLC simulation for a PlusCal spec
- `e2e/rust_tla_connect`: Rust replay testing with `tla-connect`, `rules_rust`, `rules_rs`, and `apalache_generate_traces`

## Development

Useful commands:

```bash
./tools/ci/presubmit.sh
bazel test ...
bazel test ... --experimental_output_paths=strip
bazel build //examples/plain_module:plain_module
bazel test //examples/hello_world:model_check
bazel test //examples/module_graph/spec:model_check
bazel test //examples/apalache_counter:bounded_check
bazel test //examples/apalache_counter:temporal_check
bazel test //examples/apalache_counter:simulation
cd e2e && ./bazelw test //...
cd e2e && ./bazelw test //... --experimental_output_paths=strip
```

For local formatting and file hygiene, install pre-commit and enable the hooks:

```bash
pre-commit install
pre-commit run --all-files
```
