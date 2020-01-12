java_binary(
    name = "worker",
    srcs = [
        "Tla2ToolsWorker.java",
    ],
    main_class = "io.higherkindness.rules_tla.Tla2ToolsWorker",
    visibility = ["//visibility:public"],
    deps = [
        "//third_party/bazel/src/main/protobuf:worker_protocol_java_proto",
        "@tla2tools",
    ],
)
