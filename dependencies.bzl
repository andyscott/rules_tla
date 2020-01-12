load("@bazel_tools//tools/build_defs/repo:jvm.bzl", "jvm_import_external")

def rules_tla_dependencies():
    jvm_import_external(
        name = "tla2tools",
        rule_name = "java_import",
        artifact_urls = ["https://github.com/tlaplus/tlaplus/releases/download/v1.6.0/tla2tools.jar"],
        artifact_sha256 = "71ce43150b6ee0a76cc33849ec45b2c6ae4323dc933b0acaef0928668ed0de72",
    )
