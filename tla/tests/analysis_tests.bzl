load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//tla:tla.bzl", "tla_library", "tlc_test")

def _missing_main_module_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "tlc_test could not find main module Missing.tla")
    return analysistest.end(env)

missing_main_module_test = analysistest.make(
    _missing_main_module_test_impl,
    expect_failure = True,
)

def _duplicate_module_name_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "duplicate TLA module name Shared.tla")
    return analysistest.end(env)

duplicate_module_name_test = analysistest.make(
    _duplicate_module_name_test_impl,
    expect_failure = True,
)

def analysis_test_suite(name):
    tla_library(
        name = "single_module_spec_under_test",
        srcs = ["SingleModule.tla"],
        tags = ["manual"],
    )

    tlc_test(
        name = "missing_main_module_target_under_test",
        cfg = "single.cfg",
        main_module = "Missing",
        spec = ":single_module_spec_under_test",
        tags = ["manual"],
    )

    missing_main_module_test(
        name = "missing_main_module_test",
        target_under_test = ":missing_main_module_target_under_test",
    )

    tla_library(
        name = "duplicate_module_graph_target_under_test",
        srcs = ["Root.tla"],
        deps = [
            "//tla/tests/dup_a:shared",
            "//tla/tests/dup_b:shared",
        ],
        tags = ["manual"],
    )

    duplicate_module_name_test(
        name = "duplicate_module_name_test",
        target_under_test = ":duplicate_module_graph_target_under_test",
    )

    native.test_suite(
        name = name,
        tests = [
            ":missing_main_module_test",
            ":duplicate_module_name_test",
        ],
    )
