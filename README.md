# `rules_tla`

`rules_tla` provides Bazel rules for validating TLA+ modules with SANY, translating
PlusCal modules, and running TLC from Bazel.

Current shape:

- Bzlmod only
- Bazel 9 oriented
- `BUILD.bazel` naming
- separate rules for plain TLA and PlusCal

## Installation

Add the module to `MODULE.bazel`:

```starlark
bazel_dep(name = "io_higherkindness_rules_tla", version = "<pinned version>")
```

When developing against a local checkout, use `local_path_override` instead:

```starlark
bazel_dep(name = "io_higherkindness_rules_tla", version = "0.0.0")
local_path_override(
    module_name = "io_higherkindness_rules_tla",
    path = "/absolute/path/to/rules_tla",
)
```

Load the rules from `@io_higherkindness_rules_tla//tla:tla.bzl`.

## Rule Overview

### `tla_library`

Use `tla_library` for plain `.tla` modules that are already valid TLA+.

```starlark
load("@io_higherkindness_rules_tla//tla:tla.bzl", "tla_library")

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
load("@io_higherkindness_rules_tla//tla:tla.bzl", "pluscal_library")

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
load("@io_higherkindness_rules_tla//tla:tla.bzl", "tlc_test")

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

### `tlc_simulation`

Use `tlc_simulation` for manual or exploratory TLC simulation.

```starlark
load("@io_higherkindness_rules_tla//tla:tla.bzl", "tlc_simulation")

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

`tla_simulation` remains available as a backward-compatible alias, but new code should prefer
`tlc_simulation`.

## Module Graphs

Specs can depend on other module libraries through `deps`. The main module is resolved by
module name, not by source ordering.

```starlark
load("@io_higherkindness_rules_tla//tla:tla.bzl", "tla_library", "tlc_test")

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
- `examples/simple_bank_transfer`: manual TLC simulation for a PlusCal spec

## Development

Useful commands:

```bash
bazel test ...
bazel build //examples/plain_module:plain_module
bazel test //examples/hello_world:model_check
bazel test //examples/module_graph/spec:model_check
cd e2e && bazel test //...
```
