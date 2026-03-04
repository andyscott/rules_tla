package io.higherkindness.rules_tla;

import com.google.devtools.build.lib.worker.WorkerProtocol;
import java.io.File;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Pattern;

final class Tla2ToolsWorker {
    private static final Pattern PLUSCAL_PATTERN = Pattern.compile("--(?:fair\\s+)?algorithm\\b");

    private Tla2ToolsWorker() {}

    public static void main(String[] workerArgs) throws Exception {
        if (workerArgs.length > 0 && "--persistent_worker".equals(workerArgs[0])) {
            runPersistentWorker();
            return;
        }

        Result result = runRequest(Request.fromArgs(Arrays.asList(workerArgs)), Paths.get("").toAbsolutePath());
        if (!result.output.isEmpty()) {
            System.err.print(result.output);
        }
        if (result.exitCode != 0) {
            System.exit(result.exitCode);
        }
    }

    private static void runPersistentWorker() throws IOException {
        while (true) {
            WorkerProtocol.WorkRequest request = WorkerProtocol.WorkRequest.parseDelimitedFrom(System.in);
            if (request == null) {
                return;
            }
            if (request.getCancel()) {
                continue;
            }

            Result result;
            try {
                Path workDir = resolveWorkDir(request.getSandboxDir());
                result = runRequest(Request.fromArgs(request.getArgumentsList()), workDir);
            } catch (Exception e) {
                result = Result.failure(stackTrace(e));
            }

            WorkerProtocol.WorkResponse.newBuilder()
                .setExitCode(result.exitCode)
                .setOutput(result.output)
                .setRequestId(request.getRequestId())
                .build()
                .writeDelimitedTo(System.out);
            System.out.flush();
        }
    }

    private static Result runRequest(Request request, Path workDir) throws Exception {
        switch (request.mode) {
            case "sany":
                return runSany(request, workDir);
            case "translate":
                return runTranslate(request, workDir);
            case "tlc_simulation":
                return runTlcSimulation(request, workDir);
            case "tlc_check":
                return runTlcCheck(request, workDir);
            default:
                return Result.failure("Unknown worker mode: " + request.mode);
        }
    }

    private static Result runSany(Request request, Path workDir) throws Exception {
        if (request.args.size() < 3) {
            return Result.failure("sany expects a success file, a direct module count, and module files");
        }

        Path successFile = resolvePath(workDir, request.args.get(0));
        int directModuleCount;
        try {
            directModuleCount = Integer.parseInt(request.args.get(1));
        } catch (NumberFormatException e) {
            return Result.failure("Invalid direct module count for sany: " + request.args.get(1));
        }

        List<Path> moduleFiles = new ArrayList<>();
        for (int i = 2; i < request.args.size(); i++) {
            moduleFiles.add(resolvePath(workDir, request.args.get(i)));
        }

        if (directModuleCount < 1 || directModuleCount > moduleFiles.size()) {
            return Result.failure("sany direct module count must be between 1 and " + moduleFiles.size());
        }

        Path scratchDir = Files.createTempDirectory(workDir, "rules_tla_sany_");
        try {
            List<Path> stagedModules = stageModuleFiles(moduleFiles, scratchDir);
            List<String> toolArgs = new ArrayList<>();
            toolArgs.add("-S");
            for (int i = 0; i < directModuleCount; i++) {
                toolArgs.add(stagedModules.get(i).toString());
            }

            Result toolResult = runTool("tla2sany.SANY", toolArgs, scratchDir);
            if (toolResult.exitCode == 0) {
                touch(successFile);
            }
            return toolResult;
        } finally {
            deleteRecursively(scratchDir);
        }
    }

    private static Result runTranslate(Request request, Path workDir) throws Exception {
        if (request.args.size() != 3) {
            return Result.failure("translate expects a source file, a .tla output, and a .cfg output");
        }

        Path source = resolvePath(workDir, request.args.get(0));
        Path tlaOutput = resolvePath(workDir, request.args.get(1));
        Path cfgOutput = resolvePath(workDir, request.args.get(2));

        if (!containsPlusCal(source)) {
            return Result.failure("pluscal_library expected a PlusCal algorithm in " + source.getFileName());
        }

        Path scratchDir = Files.createTempDirectory(workDir, "rules_tla_pcal_");
        try {
            Path stagedSource = scratchDir.resolve(source.getFileName().toString());
            Files.copy(source, stagedSource, StandardCopyOption.REPLACE_EXISTING);

            Result toolResult = runTool("pcal.trans", List.of(stagedSource.toString()), scratchDir);
            if (toolResult.exitCode != 0) {
                return toolResult;
            }

            copyFile(stagedSource, tlaOutput);
            copyFile(changeExtension(stagedSource, ".cfg"), cfgOutput);
            return toolResult;
        } finally {
            deleteRecursively(scratchDir);
        }
    }

    private static Result runTlcSimulation(Request request, Path workDir) throws Exception {
        if (request.args.size() < 7) {
            return Result.failure(
                "tlc_simulation expects a spec, cfg, log output, success file, max depth, max traces, and module files"
            );
        }

        int maxDepth = parsePositiveInt(request.args.get(4), "tlc_simulation max depth");
        int maxTraces = parsePositiveInt(request.args.get(5), "tlc_simulation max traces");

        Result toolResult = runTlc(
            workDir,
            resolvePath(workDir, request.args.get(0)),
            resolvePath(workDir, request.args.get(1)),
            resolvePath(workDir, request.args.get(2)),
            collectModuleFiles(request.args, workDir, 6),
            true,
            maxDepth,
            maxTraces
        );
        Path successFile = resolvePath(workDir, request.args.get(3));

        if (toolResult.exitCode == 0) {
            touch(successFile);
        }
        return toolResult;
    }

    private static Result runTlcCheck(Request request, Path workDir) throws Exception {
        if (request.args.size() < 4) {
            return Result.failure("tlc_check expects a spec, cfg, log output, and module files");
        }

        return runTlc(
            workDir,
            resolvePath(workDir, request.args.get(0)),
            resolvePath(workDir, request.args.get(1)),
            resolvePath(workDir, request.args.get(2)),
            collectModuleFiles(request.args, workDir, 3),
            false,
            0,
            0
        );
    }

    private static Result runTlc(
        Path workDir,
        Path spec,
        Path cfg,
        Path logFile,
        List<Path> moduleFiles,
        boolean simulate,
        int maxDepth,
        int maxTraces
    ) throws Exception {
        createParentDirectory(logFile);

        Path scratchDir = Files.createTempDirectory(workDir, "rules_tla_tlc_");
        try {
            List<Path> stagedModules = stageModuleFiles(moduleFiles, scratchDir);
            Path stagedSpec = scratchDir.resolve(spec.getFileName().toString());
            if (!Files.exists(stagedSpec)) {
                return Result.failure("Spec module was not staged for TLC: " + spec.getFileName());
            }

            Path stagedCfg = scratchDir.resolve(cfg.getFileName().toString());
            Files.copy(cfg, stagedCfg, StandardCopyOption.REPLACE_EXISTING);

            List<String> args = new ArrayList<>();
            args.add("-config");
            args.add(stagedCfg.toString());
            if (simulate) {
                args.add("-depth");
                args.add(Integer.toString(maxDepth));
                args.add("-simulate");
                args.add("num=" + maxTraces);
            }
            args.add(stagedSpec.toString());
            args.add("-userFile");
            args.add(logFile.toString());

            return runTool("tlc2.TLC", args, scratchDir);
        } finally {
            deleteRecursively(scratchDir);
        }
    }

    private static Result runTool(String className, List<String> args, Path workDir) throws Exception {
        List<String> command = new ArrayList<>();
        command.add(findJavaBinary());
        command.add("-cp");
        command.add(buildChildClasspath());
        command.add(className);
        command.addAll(args);

        Process process = new ProcessBuilder(command)
            .directory(workDir.toFile())
            .redirectErrorStream(true)
            .start();

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (InputStream processOutput = process.getInputStream()) {
            processOutput.transferTo(out);
        }

        int exitCode = process.waitFor();
        return Result.of(exitCode, new String(out.toByteArray(), StandardCharsets.UTF_8));
    }

    private static boolean containsPlusCal(Path source) throws IOException {
        String contents = Files.readString(source, StandardCharsets.UTF_8);
        return PLUSCAL_PATTERN.matcher(contents).find();
    }

    private static int parsePositiveInt(String value, String description) {
        final int parsed;
        try {
            parsed = Integer.parseInt(value);
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(description + " must be an integer: " + value, e);
        }
        if (parsed < 1) {
            throw new IllegalArgumentException(description + " must be at least 1: " + value);
        }
        return parsed;
    }

    private static Path resolveWorkDir(String sandboxDir) {
        if (sandboxDir == null || sandboxDir.isEmpty()) {
            return Paths.get("").toAbsolutePath();
        }
        return Paths.get(sandboxDir).toAbsolutePath();
    }

    private static Path resolvePath(Path workDir, String rawPath) {
        Path path = Paths.get(rawPath);
        if (path.isAbsolute()) {
            return path;
        }
        return workDir.resolve(path).normalize();
    }

    private static Path changeExtension(Path path, String extension) {
        String fileName = path.getFileName().toString();
        int dotIndex = fileName.lastIndexOf('.');
        String stem = dotIndex >= 0 ? fileName.substring(0, dotIndex) : fileName;
        return path.resolveSibling(stem + extension);
    }

    private static void touch(Path path) throws IOException {
        createParentDirectory(path);
        Files.write(path, new byte[0], StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING);
    }

    private static void copyFile(Path source, Path destination) throws IOException {
        createParentDirectory(destination);
        Files.copy(source, destination, StandardCopyOption.REPLACE_EXISTING);
    }

    private static List<Path> collectModuleFiles(List<String> args, Path workDir, int startIndex) {
        List<Path> moduleFiles = new ArrayList<>();
        for (int i = startIndex; i < args.size(); i++) {
            moduleFiles.add(resolvePath(workDir, args.get(i)));
        }
        return moduleFiles;
    }

    private static List<Path> stageModuleFiles(List<Path> moduleFiles, Path destinationDir) throws IOException {
        List<Path> stagedFiles = new ArrayList<>(moduleFiles.size());
        for (Path moduleFile : moduleFiles) {
            Path stagedFile = destinationDir.resolve(moduleFile.getFileName().toString());
            if (Files.exists(stagedFile) && !Files.isSameFile(moduleFile, stagedFile)) {
                throw new IOException("Duplicate TLA module name detected: " + moduleFile.getFileName());
            }
            Files.copy(moduleFile, stagedFile, StandardCopyOption.REPLACE_EXISTING);
            stagedFiles.add(stagedFile);
        }
        return stagedFiles;
    }

    private static void createParentDirectory(Path path) throws IOException {
        Path parent = path.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
    }

    private static void deleteRecursively(Path root) throws IOException {
        if (root == null || !Files.exists(root)) {
            return;
        }

        Files.walkFileTree(root, new SimpleFileVisitor<Path>() {
            @Override
            public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
                Files.deleteIfExists(file);
                return FileVisitResult.CONTINUE;
            }

            @Override
            public FileVisitResult postVisitDirectory(Path dir, IOException exc) throws IOException {
                if (exc != null) {
                    throw exc;
                }
                Files.deleteIfExists(dir);
                return FileVisitResult.CONTINUE;
            }
        });
    }

    private static String findJavaBinary() {
        return Path.of(System.getProperty("java.home"), "bin", "java").toString();
    }

    private static String buildChildClasspath() {
        String rawClasspath = System.getProperty("java.class.path");
        String[] entries = rawClasspath.split(Pattern.quote(File.pathSeparator));
        Path currentWorkingDirectory = Paths.get("").toAbsolutePath();
        Path runfilesRoot = resolveRunfilesRoot();
        List<String> resolvedEntries = new ArrayList<>(entries.length);
        for (String entry : entries) {
            Path entryPath = Paths.get(entry);
            if (entryPath.isAbsolute()) {
                resolvedEntries.add(entry);
            } else {
                Path relativeToCurrentDirectory = currentWorkingDirectory.resolve(entryPath).normalize();
                if (Files.exists(relativeToCurrentDirectory)) {
                    resolvedEntries.add(relativeToCurrentDirectory.toString());
                } else {
                    resolvedEntries.add(runfilesRoot.resolve(entryPath).normalize().toString());
                }
            }
        }
        return String.join(File.pathSeparator, resolvedEntries);
    }

    private static Path resolveRunfilesRoot() {
        String javaRunfiles = System.getenv("JAVA_RUNFILES");
        if (javaRunfiles != null && !javaRunfiles.isEmpty()) {
            Path runfilesRoot = Paths.get(javaRunfiles).toAbsolutePath();
            Path mainRepoRoot = runfilesRoot.resolve("_main");
            if (Files.isDirectory(mainRepoRoot)) {
                return mainRepoRoot;
            }
            return runfilesRoot;
        }
        return Paths.get("").toAbsolutePath();
    }

    private static String stackTrace(Exception e) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        e.printStackTrace(new PrintStream(out));
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }

    private static final class Request {
        private final String mode;
        private final List<String> args;

        private Request(String mode, List<String> args) {
            this.mode = mode;
            this.args = args;
        }

        private static Request fromArgs(List<String> args) {
            if (args.isEmpty()) {
                return new Request("", List.of());
            }
            return new Request(args.get(0), List.copyOf(args.subList(1, args.size())));
        }
    }

    private static final class Result {
        private final int exitCode;
        private final String output;

        private Result(int exitCode, String output) {
            this.exitCode = exitCode;
            this.output = output;
        }

        private static Result of(int exitCode, String output) {
            return new Result(exitCode, output);
        }

        private static Result success() {
            return new Result(0, "");
        }

        private static Result failure(String output) {
            return new Result(1, output);
        }
    }
}
