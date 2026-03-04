"""Bzlmod extension entry points for rules_tla."""

load(":repositories.bzl", "apalache_repository", "tla2tools_repository")

_DEFAULT_VERSION = "1.7.4"
_DEFAULT_SHA256 = "936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"
_DEFAULT_APALACHE_VERSION = "0.52.1"
_DEFAULT_APALACHE_SHA256 = "c539711703fd2550d8e065e486f0cbc8286846e14c16e92ef93ba3ece0149ef3"

tla_toolchain = tag_class(attrs = {
    "version": attr.string(default = _DEFAULT_VERSION),
    "sha256": attr.string(default = _DEFAULT_SHA256),
})

apalache = tag_class(attrs = {
    "version": attr.string(default = _DEFAULT_APALACHE_VERSION),
    "sha256": attr.string(default = _DEFAULT_APALACHE_SHA256),
})

def _tla_extension_impl(module_ctx):
    registrations = []
    apalache_registrations = []

    for mod in module_ctx.modules:
        registrations.extend(mod.tags.toolchain)
        apalache_registrations.extend(mod.tags.apalache)

    if not registrations:
        registrations = [struct(version = _DEFAULT_VERSION, sha256 = _DEFAULT_SHA256)]

    selected = registrations[-1]

    tla2tools_repository(
        name = "tla2tools",
        sha256 = selected.sha256,
        version = selected.version,
    )

    if apalache_registrations:
        selected_apalache = apalache_registrations[-1]
        apalache_repository(
            name = "apalache",
            sha256 = selected_apalache.sha256,
            version = selected_apalache.version,
        )

    return module_ctx.extension_metadata(reproducible = True)

tla = module_extension(
    implementation = _tla_extension_impl,
    tag_classes = {
        "apalache": apalache,
        "toolchain": tla_toolchain,
    },
    arch_dependent = False,
    os_dependent = False,
)
