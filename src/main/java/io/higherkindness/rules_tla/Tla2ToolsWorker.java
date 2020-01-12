package io.higherkindness.rules_tla;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintStream;
import java.lang.SecurityManager;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.Permission;
import java.util.ArrayList;
import java.util.List;
import java.util.LinkedList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import com.google.devtools.build.lib.worker.WorkerProtocol;

final class Tla2ToolsWorker {

    final static class ExitTrapped extends RuntimeException {
	final int code;
	ExitTrapped(int code) {
	    super();
	    this.code = code;
	}
    }

    private static final Pattern exitPattern =
	Pattern.compile("exitVM\\.(-?\\d+)");

    public static void main(String workerArgs[]) {
	if (workerArgs.length > 0 && workerArgs[0].equals("--persistent_worker")) {

	    List<Path> writtenFiles = new LinkedList<>();

	    System.setSecurityManager(new SecurityManager() {
		    @Override
		    public void checkPermission(Permission permission) {
			Matcher matcher = exitPattern.matcher(permission.getName());
			if (matcher.find())
			    throw new ExitTrapped(Integer.parseInt(matcher.group(1)));
		    }
		    @Override
		    public void checkWrite(String file) {
			writtenFiles.add(Paths.get(file));
		    }

		});

	    InputStream stdin = System.in;
	    PrintStream stdout = System.out;
	    PrintStream stderr = System.err;
	    ByteArrayOutputStream outStream = new ByteArrayOutputStream();
	    PrintStream out = new PrintStream(outStream);

	    System.setIn(new ByteArrayInputStream(new byte[0]));
	    System.setOut(out);
	    System.setErr(out);

	    try {
		while (true) {
		    WorkerProtocol.WorkRequest request =
			WorkerProtocol.WorkRequest.parseDelimitedFrom(stdin);

		    String genfilesDir = null;
		    String labelPackage = null;
		    String labelName = null;
		    String className = null;
		    boolean checkExit = true;

		    int code = 0;
		    writtenFiles.clear();

		    try {
			List<String> argList = request.getArgumentsList();
			int numArgs = argList.size();
			if (numArgs >= 5) {
			    genfilesDir = argList.get(0);
			    labelPackage = argList.get(1);
			    labelName = argList.get(2);
			    checkExit = Boolean.parseBoolean(argList.get(3));
			    className = argList.get(4);

			    String[] args = new String[numArgs - 5];
			    for (int i = 5; i < numArgs; i++) {
				args[i - 5] = argList.get(i);
			    }

			    Method main = Class.forName(className).getMethod("main", String[].class);
			    main.setAccessible(true);
			    main.invoke(null, (Object) args);
			}
		    } catch (InvocationTargetException e) {
			Throwable cause = e.getCause();
			if (cause instanceof ExitTrapped) {
			    code = ((ExitTrapped) cause).code;
			} else {
			    System.err.println(cause.getMessage());
			    cause.printStackTrace();
			    code = 1;
			}
		    } catch (ExitTrapped e) {
			code = e.code;
		    } catch (Exception e) {
			System.err.println(e.getMessage());
			e.printStackTrace();
			code = 1;
		    }

		    Path genfilesPath = Paths.get(genfilesDir);

		    String prefix = labelPackage;
		    List<Path> copyFiles = writtenFiles.stream().filter(f -> f.startsWith(prefix)).collect(Collectors.toList());

		    if (copyFiles.isEmpty())
			Files.createFile(Paths.get(genfilesDir, labelPackage, labelName + "." + className + ".success"));
		    else {
			for (Path f : copyFiles) {
			    Files.copy(f, genfilesPath.resolve(f), StandardCopyOption.REPLACE_EXISTING);
			}
		    }

		    WorkerProtocol.WorkResponse.newBuilder()
			.setOutput(outStream.toString())
			.setExitCode(checkExit ? code : 0)
			.build()
			.writeDelimitedTo(stdout);

		    out.flush();
		    outStream.reset();
		}
	    } catch (IOException e) {
	    } finally {
		System.setIn(stdin);
		System.setOut(stdout);
		System.setErr(stderr);
	    }
	}
    }
}
