#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -n "${BAZEL:-}" ]]; then
  bazel_cmd=("$BAZEL")
elif command -v bazelisk >/dev/null 2>&1; then
  bazel_cmd=("bazelisk")
else
  bazel_cmd=("bazel")
fi

run() {
  echo
  echo "==> $*"
  "$@"
}

run_bazel() {
  run "${bazel_cmd[@]}" "$@"
}

cd "$repo_root"

run_bazel run //.github/workflows:buildifier.check
run_bazel test ...
run_bazel test \
  //examples/plain_module:plain_module \
  //examples/hello_world:model_check \
  //examples/module_graph/spec:model_check \
  --experimental_output_paths=strip

(
  cd e2e
  ./bazelw test //...
  ./bazelw test \
    //rust_tla_connect:counter_model_check \
    //rust_tla_connect:trace_replay_test \
    //smoke:build_smoke \
    //smoke:hello_model_check \
    --experimental_output_paths=strip

  negative_log="$(mktemp)"
  trap 'rm -f "$negative_log"' EXIT

  if ./bazelw build //negative_pluscal:bad_spec_under_test >"$negative_log" 2>&1; then
    cat "$negative_log"
    echo "expected //negative_pluscal:bad_spec_under_test to fail" >&2
    exit 1
  fi

  if ! grep -q "expected a PlusCal algorithm" "$negative_log"; then
    cat "$negative_log"
    echo "negative_pluscal failed for an unexpected reason" >&2
    exit 1
  fi
)
