workspace(name = "io_higherkindness_rules_tla")

load("//:dependencies.bzl", "rules_tla_dependencies")

rules_tla_dependencies()

load("//tools/workspace_defs:github.bzl", "github_repository")

github_repository(
    name = "com_google_protobuf",
    archive_sha = "f9f8819bf9dccb2295f8060b177f74d36a172b7c983416fe4e4c2cea9653c1bf",
    ref = "04a11fc91668884d1793bff2a0f72ee6ce4f5edd",
    repo = "protocolbuffers/protobuf",
)

load("@com_google_protobuf//:protobuf_deps.bzl", "protobuf_deps")

protobuf_deps()
