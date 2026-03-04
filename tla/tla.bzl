_PROPAGATABLE_TAGS = [
    "no-remote",
    "no-cache",
    "no-sandbox",
    "no-remote-exec",
    "no-remote-cache",
]

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
        "files": "a depset of tla files",
    },
)

def _action_tla2sany_sany(ctx, tla, inputs):
    success_file = ctx.actions.declare_file("{}.tla2sany.SANY.success".format(ctx.label.name))
    outputs = [success_file]

    args = ctx.actions.args()
    args.add("sany")
    args.add(success_file)
    args.add_all(inputs)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run(
        mnemonic = "Tla2Tools",
        inputs = inputs,
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
    inputs = depset(ctx.files.srcs)
    outputs = depset()

    tla = _tla(ctx)
    sany_output = _action_tla2sany_sany(ctx, tla, ctx.files.srcs).success_file

    pcals = [_action_pcal_trans(ctx, tla, f) for f in ctx.files.srcs]

    pcal_outputs = [of for pcal in pcals for of in pcal.outputs]

    tla_files = [pcal.tla_file for pcal in pcals]

    tla_info = TlaInfo(
        files = depset(tla_files),
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
        "srcs": attr.label_list(allow_files = True),
        "_worker": attr.label(
            cfg = "exec",
            default = "//src/main/java/io/higherkindness/rules_tla:worker",
            executable = True,
        ),
    },
)

def _action_tlc2_TLC(ctx, tla, file, cfg):
    success_file = ctx.actions.declare_file("{}.tlc2.TLC.success".format(ctx.label.name))

    log_file = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    staged_cfg = _stage_input_file(ctx, cfg, "{}.cfg".format(ctx.label.name))

    outputs = [success_file, log_file]

    args = ctx.actions.args()
    args.add("tlc_simulation")
    args.add(file)
    args.add(staged_cfg)
    args.add(log_file)
    args.add(success_file)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run(
        mnemonic = "Tla2Tools",
        inputs = [file, staged_cfg],
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
    spec_files = ctx.attr.spec[TlaInfo].files.to_list()
    if len(spec_files) != 1:
        fail("tla_simulation requires a spec with exactly one module file, got {}".format(len(spec_files)))
    result = _action_tlc2_TLC(ctx, tla, spec_files[0], ctx.file.cfg)

    default_info = DefaultInfo(
        files = depset(result.outputs),
    )

    return [
        default_info,
    ]

tla_simulation = rule(
    implementation = _tla_simulation_implementation,
    attrs = {
        "spec": attr.label(providers = [TlaInfo]),
        "cfg": attr.label(allow_single_file = True),
        "_worker": attr.label(
            cfg = "exec",
            default = "//src/main/java/io/higherkindness/rules_tla:worker",
            executable = True,
        ),
    },
)
