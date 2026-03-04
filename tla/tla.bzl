"""Public Bazel rules for TLA+, PlusCal, TLC, and Apalache."""

_PROPAGATABLE_TAGS = [
    "no-remote",
    "no-cache",
    "no-sandbox",
    "no-remote-exec",
    "no-remote-cache",
]

_SUPPORTS_PATH_MAPPING_REQUIREMENT = {"supports-path-mapping": "1"}

_RUNFILES_BASH_INIT = """\
# --- begin runfiles.bash initialization ---
set -euo pipefail
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  if [[ -f "$0.runfiles_manifest" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
  elif [[ -f "$0.runfiles/MANIFEST" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
  elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d " " -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---
"""

def _sh_string_literal(value):
    return '"{}"'.format(value.replace("\\", "\\\\").replace('"', '\\"'))

def _resolve_execution_reqs(ctx, base_exec_reqs):
    exec_reqs = {}
    for tag in ctx.attr.tags:
        if tag in _PROPAGATABLE_TAGS:
            exec_reqs.update({tag: "1"})
    exec_reqs.update(base_exec_reqs)
    return exec_reqs

def _tla(ctx):
    toolchain = ctx.toolchains["//tla:toolchain_type"]
    java_runtime = ctx.toolchains["@bazel_tools//tools/jdk:runtime_toolchain_type"].java_runtime
    return struct(
        ctx = ctx,
        files = toolchain.files,
        jar = toolchain.jar,
        java_executable_exec_path = java_runtime.java_executable_exec_path,
        java_executable_runfiles_path = java_runtime.java_executable_runfiles_path,
        java_runtime = java_runtime,
    )

def _tla_tool_inputs(tla):
    return depset(transitive = [
        tla.files,
        tla.java_runtime.files,
    ])

def _stage_input_file(ctx, file, stem):
    staged = ctx.actions.declare_file("{}.{}".format(stem, file.basename))
    ctx.actions.symlink(
        output = staged,
        target_file = file,
    )
    return staged

TlaInfo = provider(
    doc = "Provides TLA files",
    fields = {
        "direct_module_files": "the direct .tla modules contributed by this target",
        "module_files": "a depset of all .tla modules in this target's transitive graph",
    },
)

ApalacheTraceInfo = provider(
    doc = "Provides an Apalache-generated corpus of replayable ITF traces.",
    fields = {
        "trace_corpus": "file containing a JSON array of ITF traces",
        "trace_dir": "directory artifact containing flattened .itf.json traces",
    },
)

def _action_tla2sany_sany(ctx, tla, direct_inputs, all_inputs):
    success_file = ctx.actions.declare_file("{}.tla2sany.SANY.success".format(ctx.label.name))
    outputs = [success_file]

    args = ctx.actions.args()
    args.add(tla.jar)
    args.add(success_file)
    args.add(len(direct_inputs))
    args.add_all(all_inputs)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run_shell(
        mnemonic = "Tla2Tools",
        inputs = depset(direct = all_inputs),
        outputs = outputs,
        command = """\
set -euo pipefail
if [[ "$#" -eq 1 && "$1" == @* ]]; then
  argv=()
  while IFS= read -r line; do
    argv+=("$line")
  done < "${{1#@}}"
  set -- "${{argv[@]}}"
fi

jar="$1"
success_file="$2"
direct_count="$3"
shift 3

java_bin={java_bin}
if [[ "$java_bin" != /* ]]; then
  java_bin="$PWD/$java_bin"
fi
if [[ "$jar" != /* ]]; then
  jar="$PWD/$jar"
fi

mkdir -p "$(dirname "$success_file")"

scratch_dir="$(mktemp -d "${{PWD}}/rules_tla_sany.XXXXXX")"
java_tmp_dir="$scratch_dir/java-tmp"
cleanup() {{
  rm -rf "$scratch_dir"
}}
trap cleanup EXIT
mkdir -p "$java_tmp_dir"

staged_modules=()
for module in "$@"; do
  dest="$scratch_dir/$(basename "$module")"
  if [[ -e "$dest" ]]; then
    echo >&2 "Duplicate TLA module name detected: $(basename "$module")"
    exit 1
  fi
  cp "$module" "$dest"
  staged_modules+=("$dest")
done

tool_args=(-Djava.io.tmpdir="$java_tmp_dir" -cp "$jar" tla2sany.SANY -S)
for ((i = 0; i < direct_count; i++)); do
  tool_args+=("$(basename "${{staged_modules[$i]}}")")
done

(
  cd "$scratch_dir"
  TMPDIR="$java_tmp_dir" TMP="$java_tmp_dir" TEMP="$java_tmp_dir" "$java_bin" "${{tool_args[@]}}"
)
: > "$success_file"
""".format(java_bin = _sh_string_literal(tla.java_executable_exec_path)),
        tools = _tla_tool_inputs(tla),
        execution_requirements = _resolve_execution_reqs(ctx, _SUPPORTS_PATH_MAPPING_REQUIREMENT),
        arguments = [args],
    )

    return struct(
        outputs = outputs,
        success_file = success_file,
    )

def _normalize_module_name(module_name):
    if module_name.endswith(".tla"):
        return module_name[:-4]
    return module_name

def _resolve_main_module_file(tla_info, main_module, rule_name):
    module_file_name = "{}.tla".format(_normalize_module_name(main_module))
    matches = [file for file in tla_info.module_files.to_list() if file.basename == module_file_name]
    if not matches:
        fail("{} could not find main module {}".format(rule_name, module_file_name))
    if len(matches) > 1:
        fail("{} found more than one module named {}".format(rule_name, module_file_name))
    return matches[0]

def _runfiles_path(file):
    short_path = file.short_path
    if short_path.startswith("../"):
        return short_path[3:]
    return "_main/{}".format(short_path)

def _normalize_runfiles_path(path):
    if path.startswith("/"):
        return path
    if path.startswith("../"):
        return path[3:]
    return "_main/{}".format(path)

def _shell_quote(value):
    return "'{}'".format(value.replace("'", "'\"'\"'"))

def _shell_list_arg(flag, values):
    if not values:
        return ""
    return """args+=({flag})
""".format(flag = _sh_string_literal("{}={}".format(flag, ",".join(values))))

def _ordered_module_files(direct_files, dep_infos):
    ordered_files = []
    seen_paths = {}
    seen_module_names = {}

    for file in direct_files:
        existing = seen_module_names.get(file.basename)
        if existing and existing.path != file.path:
            fail("duplicate TLA module name {} provided by {} and {}".format(file.basename, existing.path, file.path))
        ordered_files.append(file)
        seen_paths[file.path] = True
        seen_module_names[file.basename] = file

    for dep in dep_infos:
        for file in dep[TlaInfo].module_files.to_list():
            existing = seen_module_names.get(file.basename)
            if existing and existing.path != file.path:
                fail("duplicate TLA module name {} provided by {} and {}".format(file.basename, existing.path, file.path))
            if file.path in seen_paths:
                continue
            ordered_files.append(file)
            seen_paths[file.path] = True
            seen_module_names[file.basename] = file

    return ordered_files

def _module_graph(ctx, direct_tla_files):
    transitive_module_files = depset(
        direct = direct_tla_files,
        transitive = [dep[TlaInfo].module_files for dep in ctx.attr.deps],
    )
    return struct(
        ordered_module_files = _ordered_module_files(direct_tla_files, ctx.attr.deps),
        tla_info = TlaInfo(
            direct_module_files = direct_tla_files,
            module_files = transitive_module_files,
        ),
    )

def _action_pcal_trans(ctx, tla, file):
    module_name = file.basename
    if module_name.endswith(".tla"):
        module_name = module_name[:-4]

    tla_file = ctx.actions.declare_file("{}.tla".format(module_name))
    cfg_file = ctx.actions.declare_file("{}.cfg".format(module_name))
    outputs = [tla_file, cfg_file]

    args = ctx.actions.args()
    args.add(tla.jar)
    args.add(file)
    args.add(tla_file)
    args.add(cfg_file)

    ctx.actions.run_shell(
        mnemonic = "Tla2Tools",
        inputs = depset(direct = [file]),
        outputs = outputs,
        command = """\
set -euo pipefail

jar="$1"
source_file="$2"
tla_output="$3"
cfg_output="$4"

if ! grep -Eq -- '--(fair[[:space:]]+)?algorithm([[:space:][:punct:]]|$)' "$source_file"; then
  echo >&2 "pluscal_library expected a PlusCal algorithm in $(basename "$source_file")"
  exit 1
fi

mkdir -p "$(dirname "$tla_output")" "$(dirname "$cfg_output")"

scratch_dir="$(mktemp -d "${{PWD}}/rules_tla_pcal.XXXXXX")"
cleanup() {{
  rm -rf "$scratch_dir"
}}
trap cleanup EXIT

staged_source="$scratch_dir/$(basename "$source_file")"
cp "$source_file" "$staged_source"

{java_bin} -cp "$jar" pcal.trans "$staged_source"

cp "$staged_source" "$tla_output"
cp "${{staged_source%.tla}}.cfg" "$cfg_output"
""".format(java_bin = _sh_string_literal(tla.java_executable_exec_path)),
        tools = _tla_tool_inputs(tla),
        execution_requirements = _resolve_execution_reqs(ctx, _SUPPORTS_PATH_MAPPING_REQUIREMENT),
        arguments = [args],
    )

    return struct(
        outputs = outputs,
        tla_file = tla_file,
        cfg_file = cfg_file,
    )

def _tla_library_implementation(ctx):
    tla = _tla(ctx)
    module_graph = _module_graph(ctx, ctx.files.srcs)
    sany_output = _action_tla2sany_sany(ctx, tla, ctx.files.srcs, module_graph.ordered_module_files).success_file

    default_info = DefaultInfo(
        files = depset(ctx.files.srcs + [sany_output]),
    )

    return [
        default_info,
        module_graph.tla_info,
    ]

def _pluscal_library_implementation(ctx):
    tla = _tla(ctx)
    translations = [_action_pcal_trans(ctx, tla, f) for f in ctx.files.srcs]
    translation_outputs = [output for translation in translations for output in translation.outputs]
    translated_modules = [translation.tla_file for translation in translations]
    module_graph = _module_graph(ctx, translated_modules)
    sany_output = _action_tla2sany_sany(ctx, tla, translated_modules, module_graph.ordered_module_files).success_file

    return [
        DefaultInfo(
            files = depset(translation_outputs + [sany_output]),
        ),
        module_graph.tla_info,
    ]

tla_library = rule(
    implementation = _tla_library_implementation,
    attrs = {
        "deps": attr.label_list(providers = [TlaInfo]),
        "srcs": attr.label_list(allow_files = [".tla"]),
    },
    toolchains = [
        "//tla:toolchain_type",
        "@bazel_tools//tools/jdk:runtime_toolchain_type",
    ],
)

pluscal_library = rule(
    implementation = _pluscal_library_implementation,
    attrs = {
        "deps": attr.label_list(providers = [TlaInfo]),
        "srcs": attr.label_list(allow_files = [".tla"]),
    },
    toolchains = [
        "//tla:toolchain_type",
        "@bazel_tools//tools/jdk:runtime_toolchain_type",
    ],
)

def _action_tlc2_TLC(ctx, tla, main_file, module_files, cfg, max_depth, max_traces):
    success_file = ctx.actions.declare_file("{}.tlc2.TLC.success".format(ctx.label.name))

    log_file = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    staged_cfg = _stage_input_file(ctx, cfg, "{}.cfg".format(ctx.label.name))

    outputs = [success_file, log_file]

    args = ctx.actions.args()
    args.add(tla.jar)
    args.add(main_file)
    args.add(staged_cfg)
    args.add(log_file)
    args.add(success_file)
    args.add(max_depth)
    args.add(max_traces)
    args.add_all(module_files)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run_shell(
        mnemonic = "Tla2Tools",
        inputs = depset(direct = module_files + [staged_cfg]),
        outputs = outputs,
        command = """\
set -euo pipefail
if [[ "$#" -eq 1 && "$1" == @* ]]; then
  argv=()
  while IFS= read -r line; do
    argv+=("$line")
  done < "${{1#@}}"
  set -- "${{argv[@]}}"
fi

jar="$1"
spec_file="$2"
cfg_file="$3"
log_file="$4"
success_file="$5"
max_depth="$6"
max_traces="$7"
shift 7

java_bin={java_bin}
if [[ "$java_bin" != /* ]]; then
  java_bin="$PWD/$java_bin"
fi
if [[ "$jar" != /* ]]; then
  jar="$PWD/$jar"
fi

mkdir -p "$(dirname "$log_file")"
mkdir -p "$(dirname "$success_file")"

scratch_dir="$(mktemp -d "${{PWD}}/rules_tla_tlc.XXXXXX")"
cleanup() {{
  rm -rf "$scratch_dir"
}}
trap cleanup EXIT

for module in "$@"; do
  dest="$scratch_dir/$(basename "$module")"
  if [[ -e "$dest" ]]; then
    echo >&2 "Duplicate TLA module name detected: $(basename "$module")"
    exit 1
  fi
  cp "$module" "$dest"
done

staged_spec="$scratch_dir/$(basename "$spec_file")"
if [[ ! -e "$staged_spec" ]]; then
  echo >&2 "Spec module was not staged for TLC: $(basename "$spec_file")"
  exit 1
fi

staged_cfg="$scratch_dir/$(basename "$cfg_file")"
cp "$cfg_file" "$staged_cfg"

(
  cd "$scratch_dir"
  "$java_bin" -cp "$jar" tlc2.TLC \
    -config "$(basename "$staged_cfg")" \
    -depth "$max_depth" \
    -simulate "num=$max_traces" \
    "$(basename "$staged_spec")" \
    -userFile "$log_file"
)

: > "$success_file"
""".format(java_bin = _sh_string_literal(tla.java_executable_exec_path)),
        tools = _tla_tool_inputs(tla),
        execution_requirements = _resolve_execution_reqs(ctx, _SUPPORTS_PATH_MAPPING_REQUIREMENT),
        arguments = [args],
    )

    return struct(
        outputs = outputs,
        success_file = success_file,
        log_file = log_file,
    )

def _tlc_simulation_implementation(ctx):
    tla = _tla(ctx)
    if ctx.attr.max_depth < 1:
        fail("tlc_simulation max_depth must be at least 1")
    if ctx.attr.max_traces < 1:
        fail("tlc_simulation max_traces must be at least 1")

    main_file = _resolve_main_module_file(ctx.attr.spec[TlaInfo], ctx.attr.main_module, "tlc_simulation")
    result = _action_tlc2_TLC(
        ctx,
        tla,
        main_file,
        ctx.attr.spec[TlaInfo].module_files.to_list(),
        ctx.file.cfg,
        ctx.attr.max_depth,
        ctx.attr.max_traces,
    )

    default_info = DefaultInfo(
        files = depset(result.outputs),
    )

    return [
        default_info,
    ]

def _tlc_test_implementation(ctx):
    tla = _tla(ctx)
    module_files = ctx.attr.spec[TlaInfo].module_files.to_list()
    spec_file = _resolve_main_module_file(ctx.attr.spec[TlaInfo], ctx.attr.main_module, "tlc_test")
    executable = ctx.actions.declare_file(ctx.label.name)
    module_manifest = ctx.actions.declare_file("{}.modules".format(ctx.label.name))

    java_path = _normalize_runfiles_path(tla.java_executable_runfiles_path)
    jar_path = _runfiles_path(tla.jar)
    spec_path = _runfiles_path(spec_file)
    cfg_path = _runfiles_path(ctx.file.cfg)
    module_manifest_path = _runfiles_path(module_manifest)

    ctx.actions.write(
        output = module_manifest,
        content = "\n".join([_runfiles_path(file) for file in module_files]) + "\n",
    )

    script = """#!/usr/bin/env bash
{runfiles_init}

java_bin=$(rlocation {java_bin})
tool_jar=$(rlocation {tool_jar})
spec=$(rlocation {spec})
cfg=$(rlocation {cfg})
modules_manifest=$(rlocation {modules_manifest})
log_dir="${{TEST_UNDECLARED_OUTPUTS_DIR:-${{TEST_TMPDIR:-$PWD}}}}"
log_file="${{log_dir}}/{name}.tlc.log"
scratch_dir="${{TEST_TMPDIR:-$PWD}}/{name}.tlc"
mkdir -p "$log_dir"
rm -rf "$scratch_dir"
mkdir -p "$scratch_dir"

module_args=()
while IFS= read -r module_path; do
  [[ -n "$module_path" ]] || continue
  src="$(rlocation "$module_path")"
  dest="$scratch_dir/$(basename "$src")"
  if [[ -e "$dest" ]]; then
    echo >&2 "Duplicate TLA module name detected: $(basename "$src")"
    exit 1
  fi
  cp "$src" "$dest"
  module_args+=("$dest")
done < "$modules_manifest"

staged_spec="$scratch_dir/$(basename "$spec")"
if [[ ! -e "$staged_spec" ]]; then
  echo >&2 "Spec module was not staged for TLC: $(basename "$spec")"
  exit 1
fi

staged_cfg="$scratch_dir/$(basename "$cfg")"
cp "$cfg" "$staged_cfg"

if ! (
    cd "$scratch_dir"
    exec "$java_bin" -cp "$tool_jar" tlc2.TLC \
      -config "$(basename "$staged_cfg")" \
      "$(basename "$staged_spec")" \
      -userFile "$log_file"
  ); then
  if [[ -f "$log_file" ]]; then
    echo >&2
    echo >&2 "TLC user output:"
    cat >&2 "$log_file"
  fi
  exit 1
fi
""".format(
        cfg = _shell_quote(cfg_path),
        java_bin = _shell_quote(java_path),
        modules_manifest = _shell_quote(module_manifest_path),
        name = ctx.label.name,
        runfiles_init = _RUNFILES_BASH_INIT,
        spec = _shell_quote(spec_path),
        tool_jar = _shell_quote(jar_path),
    )

    ctx.actions.write(
        output = executable,
        content = script,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [
            ctx.file.cfg,
            module_manifest,
        ],
        transitive_files = depset(
            transitive = [
                depset(module_files),
                tla.files,
                tla.java_runtime.files,
            ],
        ),
    ).merge(ctx.attr._runfiles[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            executable = executable,
            runfiles = runfiles,
        ),
    ]

def _apalache_check_implementation(ctx):
    apalache = ctx.toolchains["//tla:apalache_toolchain_type"]
    java_runtime = ctx.toolchains["@bazel_tools//tools/jdk:runtime_toolchain_type"].java_runtime
    if not ctx.attr.invs and not ctx.attr.temporals:
        fail("apalache_check requires at least one invariant in invs or temporal property in temporals")
    if ctx.attr.length < 1:
        fail("apalache_check length must be at least 1")

    module_files = ctx.attr.spec[TlaInfo].module_files.to_list()
    spec_file = _resolve_main_module_file(ctx.attr.spec[TlaInfo], ctx.attr.main_module, "apalache_check")
    executable = ctx.actions.declare_file(ctx.label.name)
    module_manifest = ctx.actions.declare_file("{}.apalache.modules".format(ctx.label.name))

    ctx.actions.write(
        output = module_manifest,
        content = "\n".join([_runfiles_path(file) for file in module_files]) + "\n",
    )

    cfg_setup = ""
    cfg_arg = ""
    if ctx.file.cfg:
        cfg_setup = """cfg_src=$(rlocation {cfg})
cp "$cfg_src" "$work_dir/{cfg_basename}"
""".format(
            cfg = _shell_quote(_runfiles_path(ctx.file.cfg)),
            cfg_basename = ctx.file.cfg.basename,
        )
        cfg_arg = """args+=(--config={cfg_basename})
""".format(cfg_basename = ctx.file.cfg.basename)

    cinit_arg = ""
    if ctx.attr.cinit:
        cinit_arg = """args+=(--cinit={cinit})
""".format(cinit = ctx.attr.cinit)

    deadlock_arg = ""
    if ctx.attr.no_deadlock:
        deadlock_arg = """args+=(--no-deadlock)
"""

    property_args = _shell_list_arg("--inv", ctx.attr.invs) + _shell_list_arg("--temporal", ctx.attr.temporals)

    script = """#!/usr/bin/env bash
{runfiles_init}

resolve_path() {{
  local candidate="$1"
  if [[ "$candidate" = /* ]]; then
    printf '%s\\n' "$candidate"
  else
    rlocation "$candidate"
  fi
}}

java_bin=$(resolve_path {java_bin})
apalache_jar=$(resolve_path {apalache_jar})
modules_manifest=$(resolve_path {modules_manifest})
tmp_root="${{TEST_TMPDIR:-$PWD}}"
work_dir="${{tmp_root}}/{name}.apalache"
log_dir="${{TEST_UNDECLARED_OUTPUTS_DIR:-$work_dir/logs}}"
log_file="${{log_dir}}/{name}.apalache.log"

rm -rf "$work_dir"
mkdir -p "$work_dir" "$log_dir"

while IFS= read -r module_path; do
  [[ -n "$module_path" ]] || continue
  src=$(resolve_path "$module_path")
  cp "$src" "$work_dir/$(basename "$src")"
done < "$modules_manifest"

{cfg_setup}cd "$work_dir"

args=(
  --out-dir="$work_dir/out"
  check
  --init={init}
  --next={next}
  --length={length}
)
{property_args}{cinit_arg}{cfg_arg}{deadlock_arg}args+=({spec})

if ! "$java_bin" -jar "$apalache_jar" "${{args[@]}}" >"$log_file" 2>&1; then
  cat >&2 "$log_file"
  exit 1
fi
""".format(
        apalache_jar = _shell_quote(_runfiles_path(apalache.jar)),
        cfg_arg = cfg_arg,
        cfg_setup = cfg_setup,
        cinit_arg = cinit_arg,
        deadlock_arg = deadlock_arg,
        init = ctx.attr.init,
        java_bin = _shell_quote(_normalize_runfiles_path(java_runtime.java_executable_runfiles_path)),
        length = ctx.attr.length,
        modules_manifest = _shell_quote(_runfiles_path(module_manifest)),
        name = ctx.label.name,
        next = ctx.attr.next,
        property_args = property_args,
        runfiles_init = _RUNFILES_BASH_INIT,
        spec = _sh_string_literal(spec_file.basename),
    )

    ctx.actions.write(
        output = executable,
        content = script,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [
            module_manifest,
        ] + ([ctx.file.cfg] if ctx.file.cfg else []),
        transitive_files = depset(
            transitive = [
                depset(module_files),
                apalache.files,
                java_runtime.files,
            ],
        ),
    ).merge(ctx.attr._runfiles[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            executable = executable,
            runfiles = runfiles,
        ),
    ]

def _apalache_simulate_implementation(ctx):
    apalache = ctx.toolchains["//tla:apalache_toolchain_type"]
    java_runtime = ctx.toolchains["@bazel_tools//tools/jdk:runtime_toolchain_type"].java_runtime
    if ctx.attr.length < 1:
        fail("apalache_simulate length must be at least 1")
    if ctx.attr.max_runs < 1:
        fail("apalache_simulate max_runs must be at least 1")

    module_files = ctx.attr.spec[TlaInfo].module_files.to_list()
    spec_file = _resolve_main_module_file(ctx.attr.spec[TlaInfo], ctx.attr.main_module, "apalache_simulate")
    executable = ctx.actions.declare_file(ctx.label.name)
    module_manifest = ctx.actions.declare_file("{}.apalache.modules".format(ctx.label.name))

    ctx.actions.write(
        output = module_manifest,
        content = "\n".join([_runfiles_path(file) for file in module_files]) + "\n",
    )

    cfg_setup = ""
    cfg_arg = ""
    if ctx.file.cfg:
        cfg_setup = """cfg_src=$(rlocation {cfg})
cp "$cfg_src" "$work_dir/{cfg_basename}"
""".format(
            cfg_basename = ctx.file.cfg.basename,
            cfg = _shell_quote(_runfiles_path(ctx.file.cfg)),
        )
        cfg_arg = """args+=(--config={cfg_basename})
""".format(cfg_basename = ctx.file.cfg.basename)

    cinit_arg = ""
    if ctx.attr.cinit:
        cinit_arg = """args+=(--cinit={cinit})
""".format(cinit = ctx.attr.cinit)

    deadlock_arg = ""
    if ctx.attr.no_deadlock:
        deadlock_arg = """args+=(--no-deadlock)
"""

    property_args = _shell_list_arg("--inv", ctx.attr.invs) + _shell_list_arg("--temporal", ctx.attr.temporals)

    script = """#!/usr/bin/env bash
{runfiles_init}

resolve_path() {{
  local candidate="$1"
  if [[ "$candidate" = /* ]]; then
    printf '%s\\n' "$candidate"
  else
    rlocation "$candidate"
  fi
}}

java_bin=$(resolve_path {java_bin})
apalache_jar=$(resolve_path {apalache_jar})
modules_manifest=$(resolve_path {modules_manifest})
tmp_root="${{TEST_TMPDIR:-$PWD}}"
work_dir="${{tmp_root}}/{name}.apalache"
log_dir="${{TEST_UNDECLARED_OUTPUTS_DIR:-$work_dir/logs}}"
log_file="${{log_dir}}/{name}.apalache.log"
out_dir="${{log_dir}}/{name}.out"

rm -rf "$work_dir" "$out_dir"
mkdir -p "$work_dir" "$log_dir" "$out_dir"

while IFS= read -r module_path; do
  [[ -n "$module_path" ]] || continue
  src=$(resolve_path "$module_path")
  cp "$src" "$work_dir/$(basename "$src")"
done < "$modules_manifest"

{cfg_setup}cd "$work_dir"

args=(
  --out-dir="$out_dir"
  simulate
  --init={init}
  --next={next}
  --length={length}
  --max-run={max_runs}
)
{property_args}{cinit_arg}{cfg_arg}{deadlock_arg}args+=({spec})

if ! "$java_bin" -jar "$apalache_jar" "${{args[@]}}" >"$log_file" 2>&1; then
  cat >&2 "$log_file"
  exit 1
fi
""".format(
        apalache_jar = _shell_quote(_runfiles_path(apalache.jar)),
        cfg_arg = cfg_arg,
        cfg_setup = cfg_setup,
        cinit_arg = cinit_arg,
        deadlock_arg = deadlock_arg,
        init = ctx.attr.init,
        java_bin = _shell_quote(_normalize_runfiles_path(java_runtime.java_executable_runfiles_path)),
        length = ctx.attr.length,
        max_runs = ctx.attr.max_runs,
        modules_manifest = _shell_quote(_runfiles_path(module_manifest)),
        name = ctx.label.name,
        next = ctx.attr.next,
        property_args = property_args,
        runfiles_init = _RUNFILES_BASH_INIT,
        spec = _sh_string_literal(spec_file.basename),
    )

    ctx.actions.write(
        output = executable,
        content = script,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [
            module_manifest,
        ] + ([ctx.file.cfg] if ctx.file.cfg else []),
        transitive_files = depset(
            transitive = [
                depset(module_files),
                apalache.files,
                java_runtime.files,
            ],
        ),
    ).merge(ctx.attr._runfiles[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            executable = executable,
            runfiles = runfiles,
        ),
    ]

def _apalache_generate_traces_implementation(ctx):
    apalache = ctx.toolchains["//tla:apalache_toolchain_type"]
    java_runtime = ctx.toolchains["@bazel_tools//tools/jdk:runtime_toolchain_type"].java_runtime

    if ctx.attr.length < 1:
        fail("apalache_generate_traces length must be at least 1")
    if ctx.attr.max_traces < 1:
        fail("apalache_generate_traces max_traces must be at least 1")
    if ctx.attr.mode not in ["check", "simulate"]:
        fail("apalache_generate_traces mode must be one of check or simulate")

    module_files = ctx.attr.spec[TlaInfo].module_files.to_list()
    spec_file = _resolve_main_module_file(ctx.attr.spec[TlaInfo], ctx.attr.main_module, "apalache_generate_traces")
    trace_dir = ctx.actions.declare_directory("{}.traces".format(ctx.label.name))
    trace_corpus = ctx.actions.declare_file("{}.itf.json".format(ctx.label.name))

    args = ctx.actions.args()
    args.add(apalache.jar)
    args.add(trace_dir.path)
    args.add(trace_corpus)
    args.add(spec_file)
    args.add(ctx.file.cfg if ctx.file.cfg else "")
    args.add(ctx.attr.mode)
    args.add(ctx.attr.inv)
    args.add(ctx.attr.init)
    args.add(ctx.attr.next)
    args.add(ctx.attr.length)
    args.add(ctx.attr.max_traces)
    args.add(ctx.attr.cinit)
    args.add("1" if ctx.attr.no_deadlock else "0")
    args.add_all(module_files)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run_shell(
        mnemonic = "ApalacheGenerateTraces",
        inputs = depset(direct = module_files + ([ctx.file.cfg] if ctx.file.cfg else [])),
        outputs = [trace_dir, trace_corpus],
        command = """\
set -euo pipefail
if [[ "$#" -eq 1 && "$1" == @* ]]; then
  argv=()
  while IFS= read -r line; do
    argv+=("$line")
  done < "${{1#@}}"
  set -- "${{argv[@]}}"
fi

apalache_jar="$1"
trace_dir="$2"
trace_corpus="$3"
spec_file="$4"
cfg_file="$5"
mode="$6"
inv="$7"
init="$8"
next="$9"
length="${{10}}"
max_traces="${{11}}"
cinit="${{12}}"
no_deadlock="${{13}}"
shift 13

java_bin={java_bin}
if [[ "$java_bin" != /* ]]; then
  java_bin="$PWD/$java_bin"
fi
if [[ "$apalache_jar" != /* ]]; then
  apalache_jar="$PWD/$apalache_jar"
fi

rm -rf "$trace_dir"
mkdir -p "$trace_dir"
mkdir -p "$(dirname "$trace_corpus")"

scratch_dir="$(mktemp -d "${{PWD}}/rules_tla_apalache.XXXXXX")"
java_tmp_dir="$scratch_dir/java-tmp"
work_dir="$scratch_dir/work"
out_dir="$scratch_dir/out"
log_file="$scratch_dir/apalache.log"
cleanup() {{
  rm -rf "$scratch_dir"
}}
trap cleanup EXIT
mkdir -p "$java_tmp_dir" "$work_dir" "$out_dir"

for module in "$@"; do
  dest="$work_dir/$(basename "$module")"
  if [[ -e "$dest" ]]; then
    echo >&2 "Duplicate TLA module name detected: $(basename "$module")"
    exit 1
  fi
  cp "$module" "$dest"
done

staged_spec="$work_dir/$(basename "$spec_file")"
if [[ ! -e "$staged_spec" ]]; then
  echo >&2 "Spec module was not staged for Apalache: $(basename "$spec_file")"
  exit 1
fi

args=(
  "--out-dir=$out_dir"
  "$mode"
  "--init=$init"
  "--next=$next"
  "--length=$length"
  "--inv=$inv"
)

if [[ "$mode" == "simulate" ]]; then
  args+=("--max-run=$max_traces")
else
  args+=("--max-error=$max_traces")
fi

if [[ -n "$cfg_file" ]]; then
  staged_cfg="$work_dir/$(basename "$cfg_file")"
  cp "$cfg_file" "$staged_cfg"
  args+=("--config=$(basename "$staged_cfg")")
fi

if [[ -n "$cinit" ]]; then
  args+=("--cinit=$cinit")
fi

if [[ "$no_deadlock" == "1" ]]; then
  args+=("--no-deadlock")
fi

args+=("$(basename "$staged_spec")")

set +e
(
  cd "$work_dir"
  TMPDIR="$java_tmp_dir" TMP="$java_tmp_dir" TEMP="$java_tmp_dir" \
    "$java_bin" -Djava.io.tmpdir="$java_tmp_dir" -jar "$apalache_jar" "${{args[@]}}" >"$log_file" 2>&1
)
status="$?"
set -e

if [[ "$status" -ne 0 && "$status" -ne 12 ]]; then
  cat >&2 "$log_file"
  exit "$status"
fi

trace_count=0
first_trace=1
printf '[\n' > "$trace_corpus"
while IFS= read -r trace_file; do
  trace_count=$((trace_count + 1))
  normalized_trace="$(printf '%s/trace_%03d.itf.json' "$trace_dir" "$trace_count")"
  cp "$trace_file" "$normalized_trace"
  if [[ "$first_trace" -eq 0 ]]; then
    printf ',\n' >> "$trace_corpus"
  fi
  cat "$normalized_trace" >> "$trace_corpus"
  first_trace=0
done < <(find "$out_dir" -type f -name '*.itf.json' | sort)

printf '\n]\n' >> "$trace_corpus"

if [[ "$trace_count" -eq 0 ]]; then
  cat >&2 "$log_file"
  echo >&2 "Apalache did not produce any .itf.json traces"
  exit 1
fi
""".format(java_bin = _sh_string_literal(java_runtime.java_executable_exec_path)),
        tools = depset(transitive = [
            apalache.files,
            java_runtime.files,
        ]),
        execution_requirements = _resolve_execution_reqs(ctx, _SUPPORTS_PATH_MAPPING_REQUIREMENT),
        arguments = [args],
    )

    runfiles = ctx.runfiles(files = [trace_dir, trace_corpus])

    return [
        DefaultInfo(
            files = depset([trace_corpus]),
            runfiles = runfiles,
        ),
        ApalacheTraceInfo(
            trace_corpus = trace_corpus,
            trace_dir = trace_dir,
        ),
        OutputGroupInfo(
            trace_corpus = depset([trace_corpus]),
            trace_dir = depset([trace_dir]),
        ),
    ]

tlc_simulation = rule(
    implementation = _tlc_simulation_implementation,
    attrs = {
        "main_module": attr.string(mandatory = True),
        "max_depth": attr.int(default = 100),
        "max_traces": attr.int(default = 1),
        "spec": attr.label(providers = [TlaInfo]),
        "cfg": attr.label(allow_single_file = [".cfg"]),
    },
    toolchains = [
        "//tla:toolchain_type",
        "@bazel_tools//tools/jdk:runtime_toolchain_type",
    ],
)

tlc_test = rule(
    implementation = _tlc_test_implementation,
    test = True,
    attrs = {
        "main_module": attr.string(mandatory = True),
        "spec": attr.label(providers = [TlaInfo]),
        "cfg": attr.label(allow_single_file = [".cfg"]),
        "_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
    toolchains = [
        "//tla:toolchain_type",
        "@bazel_tools//tools/jdk:runtime_toolchain_type",
    ],
)

_apalache_check_test = rule(
    implementation = _apalache_check_implementation,
    test = True,
    attrs = {
        "cinit": attr.string(),
        "cfg": attr.label(allow_single_file = [".cfg"]),
        "init": attr.string(default = "Init"),
        "invs": attr.string_list(),
        "length": attr.int(default = 10),
        "main_module": attr.string(mandatory = True),
        "next": attr.string(default = "Next"),
        "no_deadlock": attr.bool(default = False),
        "spec": attr.label(providers = [TlaInfo]),
        "temporals": attr.string_list(),
        "_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
    toolchains = [
        "//tla:apalache_toolchain_type",
        "@bazel_tools//tools/jdk:runtime_toolchain_type",
    ],
)

def apalache_check(name, **kwargs):
    _apalache_check_test(
        name = name,
        **kwargs
    )

apalache_generate_traces = rule(
    implementation = _apalache_generate_traces_implementation,
    attrs = {
        "cfg": attr.label(allow_single_file = [".cfg"]),
        "cinit": attr.string(),
        "init": attr.string(default = "Init"),
        "inv": attr.string(mandatory = True),
        "length": attr.int(default = 10),
        "main_module": attr.string(mandatory = True),
        "max_traces": attr.int(default = 1),
        "mode": attr.string(default = "check"),
        "next": attr.string(default = "Next"),
        "no_deadlock": attr.bool(default = False),
        "spec": attr.label(providers = [TlaInfo]),
    },
    toolchains = [
        "//tla:apalache_toolchain_type",
        "@bazel_tools//tools/jdk:runtime_toolchain_type",
    ],
)

_apalache_simulate_test = rule(
    implementation = _apalache_simulate_implementation,
    test = True,
    attrs = {
        "cinit": attr.string(),
        "cfg": attr.label(allow_single_file = [".cfg"]),
        "init": attr.string(default = "Init"),
        "invs": attr.string_list(),
        "length": attr.int(default = 10),
        "main_module": attr.string(mandatory = True),
        "max_runs": attr.int(default = 1),
        "next": attr.string(default = "Next"),
        "no_deadlock": attr.bool(default = False),
        "spec": attr.label(providers = [TlaInfo]),
        "temporals": attr.string_list(),
        "_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
    toolchains = [
        "//tla:apalache_toolchain_type",
        "@bazel_tools//tools/jdk:runtime_toolchain_type",
    ],
)

def apalache_simulate(name, **kwargs):
    _apalache_simulate_test(
        name = name,
        **kwargs
    )
