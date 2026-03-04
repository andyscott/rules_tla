# Rust + `tla-connect` E2E Plan

## Goal

Produce a functional end-to-end example under Bazel where:

- `rules_tla` manages the formal TLA+/Apalache side
- a Rust test uses the `tla-connect` crate
- the Rust test runs fully inside Bazel's sandbox
- the example is covered by the repo's `e2e` validation surface

## Constraints

- Use `rules_rust` for the core Rust rule/toolchain setup
- Use `rules_rs` for Rust dependency management
- Use the `tla-connect` crate API, with local source at `/Users/ags/oss/wiggum-cc/tla-connect` as the reference
- It is acceptable to extend `rules_tla` if that makes the consumer story cleaner

## Candidate Avenues

### Avenue A: Apalache trace generation + replay

Rust test flow:

1. `tla-connect::generate_traces(...)`
2. `tla-connect::replay_traces(...)`
3. Rust driver is checked against Apalache-generated ITF traces

Pros:

- Strongest "spec drives implementation" story
- Good fit for model-based testing
- Easy to explain

Cons:

- Rust test needs an Apalache CLI entrypoint in its Bazel runtime environment
- Need a TLA spec that emits replay-friendly `action_taken` states

### Avenue B: Rust NDJSON trace validation

Rust test flow:

1. Rust emits NDJSON with `StateEmitter`
2. `tla-connect::validate_trace(...)`
3. Apalache checks the recorded behavior against a TraceSpec

Pros:

- Strong "implementation behavior is admitted by the spec" story
- May need less TLA-side machinery than replay

Cons:

- Still needs Apalache in the sandbox
- Requires a purpose-built TraceSpec

### Avenue C: Both in one demo

Use Avenue A as the main e2e story and add Avenue B if the integration cost is reasonable.

Pros:

- Best coverage of `tla-connect`
- More convincing demo for `rules_tla`

Cons:

- Higher integration and maintenance cost

## Current Working Decision

- Switch the demo to Avenue A.
- Make TLA+/Apalache trace generation its own Bazel build action so the results cache independently from Rust test execution.
- Keep the Rust side as an ordinary `rust_test` that consumes a generated trace corpus through `data` and uses `tla-connect`'s replay APIs.
- Prefer a public `rules_tla` build rule for trace generation over having Rust tests shell out to Apalache.

## Implementation Checklist

- [x] Inspect the current `rules_tla` public surface for what a Rust consumer can access
- [x] Decide how the Rust test receives an Apalache executable in Bazel
- [x] Add Rust toolchain + dependency management to `e2e/MODULE.bazel`
- [x] Create a dedicated `e2e/rust_tla_connect` package
- [x] Add Cargo metadata for the Rust example
- [x] Implement a public `rules_tla` Apalache launcher target for external consumers
- [x] Implement the Rust driver and `rust_test`
- [x] Make the Rust test pass in the Bazel sandbox
- [x] Add the new package to the `e2e` test suite / presubmit coverage
- [x] Run self-review and fix any merge-blocking issues
- [x] Add a public `apalache_generate_traces` rule that emits replayable ITF traces as Bazel outputs
- [x] Convert the Rust e2e demo from `validate_trace(...)` to `replay_traces(...)` over a generated trace corpus
- [x] Remove the Rust test's direct Apalache dependency from the runtime surface
- [x] Revalidate the split graph and update docs
- [x] Keep the final Rust consumer story explicit; do not add a Rust macro layer without stronger real-world demand

## Decision Log

- Initial read indicates `tla-connect` currently shells out to an `apalache-mc` binary for both trace generation and trace validation.
- Initial read indicates `rules_rs` is intended to pair with `rules_rust`, and its recommended migration path supports importing `rules_rust` through a `rules_rs` extension while using `rules_rs` for dependency resolution.
- The first stable path is trace validation rather than trace replay: it still exercises `tla-connect`, still runs Apalache inside Bazel, and it reuses an ordinary TLA+ model plus a purpose-built `TraceSpec`.
- `rules_tla` now needs a public executable launcher for Apalache because downstream Bazel consumers cannot reliably address the internal extension repository directly.
- The stable Rust wiring is: explicit `rules_rust` module dependency plus `rules_rs` crate resolution and toolchains, while the BUILD targets use the `rules_rs` Rust wrappers because they accept the generated crate providers cleanly. Direct `@rules_rust//rust:defs.bzl` rule loads failed analysis against the `rules_rs` crate graph.
- The completed validation surface is `cd e2e && ./bazelw test //...`, `cd e2e && ./bazelw test //... --experimental_output_paths=strip`, and the root `./tools/ci/presubmit.sh`.
- The final consumer story uses `e2e/bazelw` instead of a checked-in `.bazelrc` with a hardcoded macOS developer path. That keeps the demo runnable on this host while avoiding machine-specific configuration in the workspace itself.
- For Bazel graph quality, replay is the better primary demo than post-hoc validation: Apalache can run in a separate build action that produces a trace corpus, and the Rust test can stay a mostly normal test that only consumes those artifacts.
- Tree artifacts were not stable enough as the direct test transport under stripped output paths, so `rules_tla` now emits both a normalized trace directory and a single JSON corpus file for consumers that need a plain file.
- The implemented demo now uses a split graph:
  1. `apalache_generate_traces(...)` produces a trace corpus as a build output.
  2. An ordinary `rust_test` consumes that corpus via `data`.
  3. The Rust test parses the corpus and uses `replay_traces(...)` without shelling out to Apalache.
- A temporary Rust macro abstraction was not worth keeping. The final design leaves the BUILD graph explicit and only keeps a tiny shared Rust helper source in `rules_tla`.
