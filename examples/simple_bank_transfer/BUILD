load("@io_higherkindness_rules_tla//tla:tla.bzl", "tla_library", "tla_simulation")

tla_library(
    name = "simple_bank_tranfer",
    srcs = ["simple_bank_transfer.tla"],
)

tla_simulation(
    name = "spec",
    cfg = "demo.cfg",
    spec = ":simple_bank_tranfer",
)
