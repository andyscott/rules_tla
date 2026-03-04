_PROPAGATABLE_TAGS = [
    "no-remote",
    "no-cache",
    "no-sandbox",
    "no-remote-exec",
    "no-remote-cache",
]

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

def _resolve_execution_reqs(ctx, base_exec_reqs):
    exec_reqs = {}
    for tag in ctx.attr.tags:
        if tag in _PROPAGATABLE_TAGS:
            exec_reqs.update({tag: "1"})
    exec_reqs.update(base_exec_reqs)
    return exec_reqs

def _tla(ctx):
    worker = ctx.attr._worker
    _, _, input_manifests = ctx.resolve_command(tools = [worker])
    return struct(
        ctx = ctx,
        worker = worker,
        input_manifests = input_manifests,
    )

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
        "direct_module_files": "the translated or copied .tla files declared directly by this target",
        "module_files": "a depset of all translated or copied .tla files in this target's transitive graph",
    },
)

def _action_tla2sany_sany(ctx, tla, direct_inputs, all_inputs):
    success_file = ctx.actions.declare_file("{}.tla2sany.SANY.success".format(ctx.label.name))
    outputs = [success_file]

    args = ctx.actions.args()
    args.add("sany")
    args.add(success_file)
    args.add(len(direct_inputs))
    args.add_all(all_inputs)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run(
        mnemonic = "Tla2Tools",
        inputs = all_inputs,
        outputs = outputs,
        executable = tla.worker.files_to_run.executable,
        input_manifests = tla.input_manifests,
        execution_requirements = _resolve_execution_reqs(
            ctx,
            {"supports-workers": "1"},
        ),
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

def _shell_quote(value):
    return "'{}'".format(value.replace("'", "'\"'\"'"))

def _ordered_module_files(direct_files, dep_infos):
    ordered_files = []
    seen_paths = {}

    for file in direct_files:
        ordered_files.append(file)
        seen_paths[file.path] = True

    for dep in dep_infos:
        for file in dep[TlaInfo].module_files.to_list():
            if file.path in seen_paths:
                continue
            ordered_files.append(file)
            seen_paths[file.path] = True

    return ordered_files

def _action_pcal_trans(ctx, tla, file):
    module_name = file.basename
    if module_name.endswith(".tla"):
        module_name = module_name[:-4]

    tla_file = ctx.actions.declare_file("{}.tla".format(module_name))
    cfg_file = ctx.actions.declare_file("{}.cfg".format(module_name))
    outputs = [tla_file, cfg_file]

    args = ctx.actions.args()
    args.add("translate")
    args.add(file)
    args.add(tla_file)
    args.add(cfg_file)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run(
        mnemonic = "Tla2Tools",
        inputs = [file],
        outputs = outputs,
        executable = tla.worker.files_to_run.executable,
        input_manifests = tla.input_manifests,
        execution_requirements = _resolve_execution_reqs(
            ctx,
            {"supports-workers": "1"},
        ),
        arguments = [args],
    )

    return struct(
        outputs = outputs,
        tla_file = tla_file,
        cfg_file = cfg_file,
    )

def _tla_library_implementation(ctx):
    tla = _tla(ctx)

    pcals = [_action_pcal_trans(ctx, tla, f) for f in ctx.files.srcs]

    pcal_outputs = [of for pcal in pcals for of in pcal.outputs]

    direct_tla_files = [pcal.tla_file for pcal in pcals]
    ordered_module_files = _ordered_module_files(direct_tla_files, ctx.attr.deps)
    transitive_module_files = depset(
        direct = direct_tla_files,
        transitive = [dep[TlaInfo].module_files for dep in ctx.attr.deps],
    )
    sany_output = _action_tla2sany_sany(ctx, tla, direct_tla_files, ordered_module_files).success_file

    tla_info = TlaInfo(
        direct_module_files = direct_tla_files,
        module_files = transitive_module_files,
    )

    default_info = DefaultInfo(
        files = depset(pcal_outputs + [sany_output]),
    )

    return [
        default_info,
        tla_info,
    ]

tla_library = rule(
    implementation = _tla_library_implementation,
    attrs = {
        "deps": attr.label_list(providers = [TlaInfo]),
        "srcs": attr.label_list(allow_files = True),
        "_worker": attr.label(
            cfg = "exec",
            default = "//src/main/java/io/higherkindness/rules_tla:worker",
            executable = True,
        ),
    },
)

def _action_tlc2_TLC(ctx, tla, main_file, module_files, cfg):
    success_file = ctx.actions.declare_file("{}.tlc2.TLC.success".format(ctx.label.name))

    log_file = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    staged_cfg = _stage_input_file(ctx, cfg, "{}.cfg".format(ctx.label.name))

    outputs = [success_file, log_file]

    args = ctx.actions.args()
    args.add("tlc_simulation")
    args.add(main_file)
    args.add(staged_cfg)
    args.add(log_file)
    args.add(success_file)
    args.add_all(module_files)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run(
        mnemonic = "Tla2Tools",
        inputs = module_files + [staged_cfg],
        outputs = outputs,
        executable = tla.worker.files_to_run.executable,
        input_manifests = tla.input_manifests,
        execution_requirements = _resolve_execution_reqs(
            ctx,
            {"supports-workers": "1"},
        ),
        arguments = [args],
    )

    return struct(
        outputs = outputs,
        success_file = success_file,
        log_file = log_file,
    )

def _tla_simulation_implementation(ctx):
    tla = _tla(ctx)
    main_file = _resolve_main_module_file(ctx.attr.spec[TlaInfo], ctx.attr.main_module, "tla_simulation")
    result = _action_tlc2_TLC(ctx, tla, main_file, ctx.attr.spec[TlaInfo].module_files.to_list(), ctx.file.cfg)

    default_info = DefaultInfo(
        files = depset(result.outputs),
    )

    return [
        default_info,
    ]

def _tlc_test_implementation(ctx):
    module_files = ctx.attr.spec[TlaInfo].module_files.to_list()
    spec_file = _resolve_main_module_file(ctx.attr.spec[TlaInfo], ctx.attr.main_module, "tlc_test")
    executable = ctx.actions.declare_file(ctx.label.name)
    module_manifest = ctx.actions.declare_file("{}.modules".format(ctx.label.name))

    worker_path = _runfiles_path(ctx.executable._worker)
    spec_path = _runfiles_path(spec_file)
    cfg_path = _runfiles_path(ctx.file.cfg)
    module_manifest_path = _runfiles_path(module_manifest)

    ctx.actions.write(
        output = module_manifest,
        content = "\n".join([_runfiles_path(file) for file in module_files]) + "\n",
    )

    script = """#!/usr/bin/env bash
{runfiles_init}

worker=$(rlocation {worker})
spec=$(rlocation {spec})
cfg=$(rlocation {cfg})
modules_manifest=$(rlocation {modules_manifest})
log_dir="${{TEST_UNDECLARED_OUTPUTS_DIR:-${{TEST_TMPDIR:-$PWD}}}}"
log_file="${{log_dir}}/{name}.tlc.log"
mkdir -p "$log_dir"

module_args=()
while IFS= read -r module_path; do
  [[ -n "$module_path" ]] || continue
  module_args+=("$(rlocation "$module_path")")
done < "$modules_manifest"

if ! "$worker" tlc_check "$spec" "$cfg" "$log_file" "${{module_args[@]}}"; then
  if [[ -f "$log_file" ]]; then
    echo >&2
    echo >&2 "TLC user output:"
    cat >&2 "$log_file"
  fi
  exit 1
fi
""".format(
        cfg = _shell_quote(cfg_path),
        modules_manifest = _shell_quote(module_manifest_path),
        name = ctx.label.name,
        runfiles_init = _RUNFILES_BASH_INIT,
        spec = _shell_quote(spec_path),
        worker = _shell_quote(worker_path),
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
        transitive_files = depset(module_files),
    ).merge(ctx.attr._worker[DefaultInfo].default_runfiles).merge(ctx.attr._runfiles[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            executable = executable,
            runfiles = runfiles,
        ),
    ]

tla_simulation = rule(
    implementation = _tla_simulation_implementation,
    attrs = {
        "main_module": attr.string(mandatory = True),
        "spec": attr.label(providers = [TlaInfo]),
        "cfg": attr.label(allow_single_file = True),
        "_worker": attr.label(
            cfg = "exec",
            default = "//src/main/java/io/higherkindness/rules_tla:worker",
            executable = True,
        ),
    },
)

tlc_test = rule(
    implementation = _tlc_test_implementation,
    test = True,
    attrs = {
        "main_module": attr.string(mandatory = True),
        "spec": attr.label(providers = [TlaInfo]),
        "cfg": attr.label(allow_single_file = True),
        "_worker": attr.label(
            cfg = "target",
            default = "//src/main/java/io/higherkindness/rules_tla:worker",
            executable = True,
        ),
        "_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
)
