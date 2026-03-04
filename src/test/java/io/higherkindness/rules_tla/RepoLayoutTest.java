package io.higherkindness.rules_tla;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public final class RepoLayoutTest {
    public static void main(String[] args) {
        String testSrcDir = System.getenv("TEST_SRCDIR");
        String testWorkspace = System.getenv("TEST_WORKSPACE");

        if (testSrcDir == null || testWorkspace == null) {
            throw new IllegalStateException("Bazel test runfiles are not available");
        }

        Path repoRoot = Paths.get(testSrcDir, testWorkspace);

        assertExists(repoRoot.resolve("MODULE.bazel"));
        assertExists(repoRoot.resolve(".bazelversion"));
    }

    private static void assertExists(Path path) {
        if (!Files.exists(path)) {
            throw new IllegalStateException("Expected file to exist: " + path);
        }
    }
}
