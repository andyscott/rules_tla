package io.higherkindness.rules_tla;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

public final class E2eWorkspaceTest {
    public static void main(String[] args) throws Exception {
        Path repoRoot = resolveRepoRoot();

        runSuccess(
            repoRoot.resolve("e2e/smoke"),
            "smoke",
            List.of("test", "--test_output=errors", "//:smoke_test")
        );

        runFailure(
            repoRoot.resolve("e2e/negative_pluscal"),
            "negative_pluscal",
            List.of("build", "//:bad_spec"),
            "pluscal_library expected a PlusCal algorithm"
        );
    }

    private static Path resolveRepoRoot() {
        String testSrcDir = System.getenv("TEST_SRCDIR");
        String testWorkspace = System.getenv("TEST_WORKSPACE");

        if (testSrcDir == null || testWorkspace == null) {
            throw new IllegalStateException("Bazel test runfiles are not available");
        }

        return Paths.get(testSrcDir, testWorkspace);
    }

    private static void runSuccess(Path workspaceDir, String outputRootName, List<String> bazelArgs)
        throws Exception {
        assertExists(workspaceDir.resolve("MODULE.bazel"));

        CommandResult result = runBazel(workspaceDir, outputRootName, bazelArgs);
        if (result.exitCode != 0) {
            throw new IllegalStateException(
                "Expected Bazel command to succeed in " + workspaceDir + "\n" + result.output
            );
        }
    }

    private static void runFailure(
        Path workspaceDir,
        String outputRootName,
        List<String> bazelArgs,
        String expectedFailure
    ) throws Exception {
        assertExists(workspaceDir.resolve("MODULE.bazel"));

        CommandResult result = runBazel(workspaceDir, outputRootName, bazelArgs);
        if (result.exitCode == 0) {
            throw new IllegalStateException(
                "Expected Bazel command to fail in " + workspaceDir + "\n" + result.output
            );
        }
        if (!result.output.contains(expectedFailure)) {
            throw new IllegalStateException(
                "Expected failure output to contain: " + expectedFailure + "\n" + result.output
            );
        }
    }

    private static CommandResult runBazel(Path workspaceDir, String outputRootName, List<String> bazelArgs)
        throws Exception {
        List<String> command = new ArrayList<>();
        command.add(System.getenv().getOrDefault("BAZEL_BIN", "bazel"));
        command.add("--ignore_all_rc_files");
        command.add("--output_user_root=" + resolveOutputRoot(outputRootName));
        command.addAll(bazelArgs);

        Process process;
        try {
            process = new ProcessBuilder(command)
                .directory(workspaceDir.toFile())
                .redirectErrorStream(true)
                .start();
        } catch (IOException e) {
            throw new IllegalStateException("Failed to launch Bazel for e2e test", e);
        }

        String output;
        try (var inputStream = process.getInputStream()) {
            output = new String(inputStream.readAllBytes(), StandardCharsets.UTF_8);
        }

        return new CommandResult(process.waitFor(), output);
    }

    private static String resolveOutputRoot(String outputRootName) throws IOException {
        String testTmpDir = System.getenv("TEST_TMPDIR");
        Path tmpDir = testTmpDir == null ? Paths.get(System.getProperty("java.io.tmpdir")) : Paths.get(testTmpDir);
        Path outputRoot = tmpDir.resolve(outputRootName + "-output-root");
        Files.createDirectories(outputRoot);
        return outputRoot.toString();
    }

    private static void assertExists(Path path) {
        if (!Files.exists(path)) {
            throw new IllegalStateException("Expected file to exist: " + path);
        }
    }

    private static final class CommandResult {
        private final int exitCode;
        private final String output;

        private CommandResult(int exitCode, String output) {
            this.exitCode = exitCode;
            this.output = output;
        }
    }
}
