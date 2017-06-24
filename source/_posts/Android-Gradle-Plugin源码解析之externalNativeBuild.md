title: Android Gradle Plugin源码解析之externalNativeBuild
date: 2017-06-24 19:42:31
categories: [Android]
tags: [Android, NDK, Android Gradle Plugin]
---

在Android Studio 2.2开始的Android Gradle Plugin版本中，Google集成了对cmake的完美支持，而原先的ndkBuild的方式支持也变得更加良好。这篇文章就来说说Android Gradle Plugin与交叉编译之间的一些事，即externalNativeBuild相关的task，主要是解读一下gradle构建系统相关的源码。

<!-- more -->

### 前言

如果你在gradle中使用过cmake，你会发现在gradle执行sync操作后，项目的module目录下就会生成一个叫**.externalNativeBuild**的文件夹，该文件夹用来进行C/C++代码的编译，当然，如果你用的是ndkBuild的方式，该文件夹下的文件会发生变化，文件较cmake会少很多。

cmake方式产生的文件列表如下：

![extern-build-cmake.png](extern-build-cmake.png)

而ndkBuild方式产生的文件列表如下：

![extern-build-ndk.png](extern-build-ndk.png)

他们的共同点是都有一个叫**android_gradle_build.json**的文件，这个文件用来被Android Gradle Plugin中的externalNativeBuild任务解析，将构建命令解析出来，然后编译C/C++代码，最后产生目标so文件。除此之外，还有x_build_command.txt和x_build_output.txt两个文件，其中x表示构建方式，使用cmake的话x就等于cmake，使用ndkBuild的话x就等于ndkBuild。x_build_command.txt文件承载着构建命令，android_gradle_build.json的生成依赖它，而x_build_output.txt文件是执行x_build_command.txt中的构建命令后控制台输出的内容。

### cmake

通过查看android gradle plugin的源码，可以发现生成cmake_build_command.txt文件生成的方式其实很简单，就是一个不断拼接参数的过程，其源码在CmakeExternalNativeJsonGenerator中的getProcessBuilder，如下：

```
@NonNull
@Override
ProcessInfoBuilder getProcessBuilder(@NonNull String abi, int abiPlatformVersion,
        @NonNull File outputJson) {
    checkConfiguration();
    ProcessInfoBuilder builder = new ProcessInfoBuilder();
    // CMake requires a folder. Trim the filename off.
    File cmakeListsFolder = getMakefile().getParentFile();

    builder.setExecutable(getCmakeExecutable());
    builder.addArgs(String.format("-H%s", cmakeListsFolder));
    builder.addArgs(String.format("-B%s", outputJson.getParentFile()));
    // TODO: possibly remove the Android Gradle part.
    // Depends on how upstream CMake accepts our JSON patch.
    builder.addArgs("-GAndroid Gradle - Ninja");
    builder.addArgs(String.format("-DANDROID_ABI=%s", abi));
    builder.addArgs(String.format("-DANDROID_NDK=%s", getNdkFolder()));
    builder.addArgs(
            String.format("-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=%s",
                    new File(getObjFolder(), abi)));
    builder.addArgs(
            String.format("-DCMAKE_BUILD_TYPE=%s", isDebuggable() ? "Debug" : "Release"));
    builder.addArgs(String.format("-DCMAKE_MAKE_PROGRAM=%s",
            getNinjaExecutable().getAbsolutePath()));
    builder.addArgs(String.format("-DCMAKE_TOOLCHAIN_FILE=%s",
            getToolChainFile().getAbsolutePath()));

    builder.addArgs(String.format("-DANDROID_PLATFORM=android-%s", abiPlatformVersion));

    if (!getcFlags().isEmpty()) {
        builder.addArgs(String.format("-DCMAKE_C_FLAGS=%s", Joiner.on(" ").join(getcFlags())));
    }

    if (!getCppFlags().isEmpty()) {
        builder.addArgs(String.format("-DCMAKE_CXX_FLAGS=%s",
                Joiner.on(" ").join(getCppFlags())));
    }

    for (String argument : getBuildArguments()) {
        builder.addArgs(argument);
    }

    return builder;
}
```

该函数的返回值为ProcessInfoBuilder，该对象专门用于携带可执行文件以及可执行文件执行时需要的参数，传递给project.exec执行。

- 设置可执行文件为cmake，调用getCmakeExecutable方法，获取cmake可执行文件，调用setExecutable方法设置它
- 拼接-H参数，其值为CMakeList.txt文件所在目录
- 拼接-B参数，其值为cmake产生的中间产物，一般就是cmake_build_command.txt所在目录的父目录，cmake构建产生的中间产物全都位于此目录。
- 拼接-G参数，其值为Android Gradle - Ninja，告诉cmake生成Android Gradle需要的项目文件，并且使用ninja构建，值得注意的是，该值在标准的cmake中是不支持的，也就是说，as使用的cmake是google修改过的，通过查看其注释 **possibly remove the Android Gradle part. Depends on how upstream CMake accepts our JSON patch.** 也可以看出，google可能会移除该值中Android Gradle部分，但是还是要取决于cmake如果接受google的patch。
- 设置ANDROID_ABI参数，其值为armeabi，armeabi-v7a，arm64-v8a，x86，x86_64，mips，mips64中的一个。
- 设置ANDROID_NDK参数，其值为ndk的路径。
- 设置CMAKE_LIBRARY_OUTPUT_DIRECTORY参数，其值为so的输出路径，一般其值为项目的build路径下的intermediates/cmake/debug/obj/$ANDROID_ABI
- 设置CMAKE_BUILD_TYPE参数，是否是debug，其值为Debug或者Release中的一个，debug含符号信息，so很大，便于调试，Release移除了debug信息，小很多。其值来源于build.gradle中的debuggable值。
- 设置CMAKE_MAKE_PROGRAM参数。其值为ninja路径，因为生成的是ninja构建的项目，所以需要指定其路径。该值gradle会根据sdk和ndk的路径，自动推断出。
- 设置CMAKE_TOOLCHAIN_FILE参数，该参数是cmake用于交叉编译时设置的必要参数，主要设置一些交叉编译需要的参数，如CC，CXX，AR，AS，CFLAGS，CXXFLAGS等，可以查看[NDK 交叉编译常用变量](/2017/06/22/NDK%E4%BA%A4%E5%8F%89%E7%BC%96%E8%AF%91%E5%B8%B8%E7%94%A8%E5%8F%98%E9%87%8F/)，android.toolchain.cmake文件的代码在[android.toolchain.cmake](https://android.googlesource.com/platform/tools/cmake-utils/+/cmake-master-dev/android.toolchain.cmake)，兼容[android-cmake](https://github.com/taka-no-me/android-cmake)，该值gradle会根据sdk和ndk的路径，自动推断出。
- 设置ANDROID_PLATFORM参数，一般设成和项目的最小api版本一样即可，gradle会通过它和minSdk查找出合适的值
- 设置可选项CMAKE_C_FLAGS参数，如果不为空，则设置，其值为编译C时的一些参数
- 设置可选项CMAKE_CXX_FLAGS参数，如果不为空，则设置，其值为编译C++时的一些参数
- 设置可选项arguments，其值为gradle传进来的arguments参数。

更多参数说明见[CMake](https://developer.android.com/ndk/guides/cmake.html)

然后将该返回值转为字符串输出到文件中，该文件即cmake_build_command.txt

其内容大致如下:

```
Executable : /Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/cmake
arguments : 
-Hpath/to/CMakeFiles Parent Dir
-Bpath/to/moduleDir/.externalNativeBuild/cmake/debug/armeabi-v7a
-GAndroid Gradle - Ninja
-DANDROID_ABI=armeabi-v7a
-DANDROID_NDK=/Users/lizhangqu/AndroidNDK/android-ndk-r14b
-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=path/to/moduleDir/build/intermediates/cmake/debug/obj/armeabi-v7a
-DCMAKE_BUILD_TYPE=Debug
-DCMAKE_MAKE_PROGRAM=/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/ninja
-DCMAKE_TOOLCHAIN_FILE=/Users/lizhangqu/AndroidNDK/android-ndk-r14b/build/cmake/android.toolchain.cmake
-DANDROID_PLATFORM=android-14
-DCMAKE_C_FLAGS=-fpic -fexceptions -frtti
-DCMAKE_CXX_FLAGS=-fpic -fexceptions -frtti
-DANDROID_STL=c++_static
jvmArgs : 
```

当然我们可以直接在命令行调用之，生成cmake项目结构，如下

```
/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/cmake \
-H"path/to/CMakeFiles Parent Dir" \
-B"path/to/moduleDir/.externalNativeBuild/cmake/debug/armeabi-v7a" \
-G"Android Gradle - Ninja" \
-DANDROID_ABI="armeabi-v7a" \
-DANDROID_NDK="/Users/lizhangqu/AndroidNDK/android-ndk-r14b" \
-DCMAKE_LIBRARY_OUTPUT_DIRECTORY="path/to/moduleDir/build/intermediates/cmake/debug/obj/armeabi-v7a" \
-DCMAKE_BUILD_TYPE="Debug" \
-DCMAKE_MAKE_PROGRAM="/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/ninja" \
-DCMAKE_TOOLCHAIN_FILE="/Users/lizhangqu/AndroidNDK/android-ndk-r14b/build/cmake/android.toolchain.cmake" \
-DANDROID_PLATFORM="android-14" \
-DCMAKE_C_FLAGS="-fpic -fexceptions -frtti" \
-DCMAKE_CXX_FLAGS="-fpic -fexceptions -frtti" \
-DANDROID_STL="c++_static"
```

其对应的gradle调用代码大致如下

```
// See whether the current build command matches a previously written build command.
String currentBuildCommand = processBuilder.toString();
boolean rebuildDueToMissingPreviousCommand = false;
File commandFile = new File(expectedJson.getParentFile(),
        String.format("%s_build_command.txt", getNativeBuildSystem().getName()));
```

就是将processBuilder对象中携带的参数，调用project.exec执行即可。

```
String buildOutput = executeProcess(processBuilder);

// Write the captured process output to a file for diagnostic purposes.
File outputTextFile = new File(
        expectedJson.getParentFile(),
        String.format("%s_build_output.txt", getNativeBuildSystem().getName()));
diagnostic("write build output %s", outputTextFile.getAbsolutePath());
Files.write(buildOutput, outputTextFile, Charsets.UTF_8);
```

executeProcess执行完之后，就会产生cmake_build_output.txt文件，该文件就是执行cmake_build_command.txt中的命令之后控制台输出的内容。大致如下：

```
-- Check for working C compiler: /Users/lizhangqu/AndroidNDK/android-ndk-r14b/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang
-- Check for working C compiler: /Users/lizhangqu/AndroidNDK/android-ndk-r14b/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang -- works
-- Detecting C compiler ABI info
-- Detecting C compiler ABI info - done
-- Detecting C compile features
-- Detecting C compile features - done
-- Check for working CXX compiler: /Users/lizhangqu/AndroidNDK/android-ndk-r14b/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang++
-- Check for working CXX compiler: /Users/lizhangqu/AndroidNDK/android-ndk-r14b/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang++ -- works
-- Detecting CXX compiler ABI info
-- Detecting CXX compiler ABI info - done
-- Detecting CXX compile features
-- Detecting CXX compile features - done
-- Configuring done
-- Generating done
-- Build files have been written to: path/to/moduleDir/.externalNativeBuild/cmake/debug/armeabi-v7a

```

此外，其他文件也被一并产生，如android_gradle_build.json，build.ninja，cmake_insatll.cmake，CMakeCache.txt，rules.ninja，CMakefiles文件夹等等。

而executeProcess方法，最终调用的是GradleProcessExecutor的execute方法，然后通过其内部类ExecAction的execute方法构造ExecSpec对象，调用project.exec方法执行之。其大致源码如下:

```
@NonNull
@Override
public ProcessResult execute(
        @NonNull ProcessInfo processInfo,
        @NonNull ProcessOutputHandler processOutputHandler) {
    ProcessOutput output = processOutputHandler.createOutput();

    ExecResult result;
    try {
        result = project.exec(new ExecAction(processInfo, output));
    } finally {
        try {
            output.close();
        } catch (IOException e) {
            project.getLogger().warn("Exception while closing sub process streams", e);
        }
    }
    try {
        processOutputHandler.handleOutput(output);
    } catch (final ProcessException e) {
        return new OutputHandlerFailedGradleProcessResult(e);
    }
    return new GradleProcessResult(result, processInfo);
}

private static class ExecAction implements Action<ExecSpec> {

    @NonNull
    private final ProcessInfo processInfo;

    @NonNull
    private final ProcessOutput processOutput;

    ExecAction(@NonNull final ProcessInfo processInfo,
            @NonNull final ProcessOutput processOutput) {
        this.processInfo = processInfo;
        this.processOutput = processOutput;
    }

    @Override
    public void execute(ExecSpec execSpec) {

        /*
         * Gradle doesn't work correctly when there are empty args.
         */
        List<String> args =
                processInfo.getArgs().stream()
                        .map(a -> a.isEmpty()? "\"\"" : a)
                        .collect(Collectors.toList());
        execSpec.setExecutable(processInfo.getExecutable());
        execSpec.args(args);
        execSpec.environment(processInfo.getEnvironment());
        execSpec.setStandardOutput(processOutput.getStandardOutput());
        execSpec.setErrorOutput(processOutput.getErrorOutput());

        // we want the caller to be able to do its own thing.
        execSpec.setIgnoreExitValue(true);
    }
}
```

json文件生成了，之后就是生产so文件了，生成so文件由ExternalNativeBuildTask负责，其主要职责就是解析出android_gradle_build.json文件中libraries的各项中的的artifactName和buildCommand，传入对应的executeProcessBatch函数，执行buildCommand中的值，执行的方式也是通过GradleProcessExecutor的execute方法，最终产生so。

我们来看看android_gradle_build.json的大致内容：

```

{
	"buildFiles" : 
	[
		"path/to/CMakeLists.txt"
	],
	"cleanCommands" : 
	[
		"/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/cmake --build path/to/.externalNativeBuild/cmake/debug/armeabi-v7a --target clean"
	],
	"cppFileExtensions" : [ "cpp" ],
	"libraries" : 
	{
		"so名字-Debug-armeabi-v7a" : 
		{
			"abi" : "armeabi-v7a",
			"artifactName" : "so名字",
			"buildCommand" : "/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/cmake --build path/to/.externalNativeBuild/cmake/debug/armeabi-v7a --target so名字",
			"buildType" : "debug",
			"files" : 
			[
				
				{
					"flags" : "内容",
					"src" : "内容",
					"workingDirectory" : "path/to/.externalNativeBuild/cmake/debug/armeabi-v7a"
				},
				{
					"flags" : "内容",
					"src" : "内容",
					"workingDirectory" : "path/to/.externalNativeBuild/cmake/debug/armeabi-v7a"
				},
				{
					"flags" : "内容",
					"src" : "内容",
					"workingDirectory" : "path/to/.externalNativeBuild/cmake/debug/armeabi-v7a"
				}
			],
			"output" : "path/to/build/intermediates/cmake/debug/obj/armeabi-v7a/so名字.so",
			"toolchain" : "12644252315582812689"
		}
	},
	"toolchains" : 
	{
		"12644252315582812689" : 
		{
			"cCompilerExecutable" : "/Users/lizhangqu/AndroidNDK/android-ndk-r14b/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang",
			"cppCompilerExecutable" : "/Users/lizhangqu/AndroidNDK/android-ndk-r14b/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang++"
		}
	}
}

```

没错解析的就是libraries下"so名字-Debug-armeabi-v7a"下的artifactName和buildCommand，我们可以试试直接将buildCommand中的命令复制到命令行执行，可以看到so就会编译产生。

除了直接复制buildCommand中的命令，也可以进入到cmake生成的文件目录，即-B指定的目录，调用ninja进行构建。如：

```
/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/ninja clean

/Users/lizhangqu/AndroidSDK/cmake/3.6.3155560/bin/ninja 
```


ninja是chromium的核心构建工具，可以参考[Ninja - chromium核心构建工具](http://www.cnblogs.com/x_wukong/p/4846179.html)学习下相关的内容。

而clean操作，则由ExternalNativeCleanTask负责，其主要职责就是解析出android_gradle_build.json中的cleanCommands命令，然后执行。


### ndkBuild

和cmake类似，首先就是ndkBuild_build_command.txt的生成，其生成所需的关键参数由NdkBuildExternalNativeJsonGenerator中的getProcessBuilder函数和getBaseArgs函数负责，其代码如下：

```
@NonNull
@Override
ProcessInfoBuilder getProcessBuilder(@NonNull String abi, int abiPlatformVersion,
        @NonNull File outputJson) {
    checkConfiguration();
    // Discover Application.mk if one exists next to Android.mk
    // If there is an Application.mk file next to Android.mk then pick it up.
    File applicationMk = new File(getMakeFile().getParent(), "Application.mk");
    ProcessInfoBuilder builder = new ProcessInfoBuilder();
    builder.setExecutable(getNdkBuild())
            .addArgs(getBaseArgs(abi, abiPlatformVersion, applicationMk))
            // Disable response files so we can parse the command line.
            .addArgs("APP_SHORT_COMMANDS=false")
            .addArgs("LOCAL_SHORT_COMMANDS=false")
            .addArgs("-B") // Build as if clean
            .addArgs("-n");
    return builder;
}
/**
 * Get the base list of arguments for invoking ndk-build.
 */
@NonNull
private List<String> getBaseArgs(@NonNull String abi, int abiPlatformVersion,
        @NonNull File applicationMk) {
    List<String> result = Lists.newArrayList();
    result.add("NDK_PROJECT_PATH=null");
    result.add("APP_BUILD_SCRIPT=" + getMakeFile());

    if (applicationMk.exists()) {
        // NDK_APPLICATION_MK specifies the Application.mk file.
        result.add("NDK_APPLICATION_MK=" + applicationMk.getAbsolutePath());
    }

    // APP_ABI and NDK_ALL_ABIS work together. APP_ABI is the specific ABI for this build.
    // NDK_ALL_ABIS is the universe of all ABIs for this build. NDK_ALL_ABIS is set to just the
    // current ABI. If we don't do this, then ndk-build will erase build artifacts for all abis
    // aside from the current.
    result.add("APP_ABI=" + abi);
    result.add("NDK_ALL_ABIS=" + abi);

    if (isDebuggable()) {
        result.add("NDK_DEBUG=1");
    } else {
        result.add("NDK_DEBUG=0");
    }

    result.add("APP_PLATFORM=android-" + abiPlatformVersion);

    // getObjFolder is set to the "local" subfolder in the user specified directory, therefore,
    // NDK_OUT should be set to getObjFolder().getParent() instead of getObjFolder().
    String ndkOut = getObjFolder().getParent();
    if (CURRENT_PLATFORM == PLATFORM_WINDOWS) {
        // Due to b.android.com/219225, NDK_OUT on Windows requires forward slashes.
        // ndk-build.cmd is supposed to escape the back-slashes but it doesn't happen.
        // Workaround here by replacing back slash with forward.
        // ndk-build will have a fix for this bug in r14 but this gradle fix will make it
        // work back to r13, r12, r11, and r10.
        ndkOut = ndkOut.replace('\\', '/');
    }
    result.add("NDK_OUT=" + ndkOut);

    result.add("NDK_LIBS_OUT=" + getSoFolder().getAbsolutePath());

    for (String flag : getcFlags()) {
        result.add(String.format("APP_CFLAGS+=\"%s\"", flag));
    }

    for (String flag : getCppFlags()) {
        result.add(String.format("APP_CPPFLAGS+=\"%s\"", flag));
    }

    for (String argument : getBuildArguments()) {
        result.add(argument);
    }

    return result;
}
```

- 设置可执行文件为ndk-Build
- 设置NDK_PROJECT_PATH=null
- 设置APP_BUILD_SCRIPT参数，其值指向Android.mk文件
- 设置NDK_APPLICATION_MK参数，其值指向Application.mk文件（如果存在的话，不存在就不会设置该参数）
- 设置APP_ABI参数，其值为armeabi，armeabi-v7a，arm64-v8a，x86，x86_64，mips，mips64中的一个。
- 设置NDK_ALL_ABIS参数，其值等同于APP_ABI
- 设置NDK_DEBUG参数，表示十分是debug构建，debug含符号信息，so很大，便于调试，release移除了debug信息，小很多。其值来源于build.gradle中的debuggable值。
- 设置APP_PLATFORM参数，一般设成和项目的最小api版本一样即可，gradle会通过它和minSdk查找出合适的值
- 设置NDK_OUT参数，其值为obj文件产生目录，一般指向项目的build路径下的intermediates/ndkBuild/$buildType/obj目录
- 设置NDK_LIBS_OUT参数，其值为libs参数目录，用于so的存储，一般指向项目的build路径下的intermediates/ndkBuild/$buildType/lib目录
- 设置可选项APP_CFLAGS参数，如果不为空，则设置，其值为编译C时的一些参数
- 设置可选项APP_CPPFLAGS参数，如果不为空，则设置，其值为编译C++时的一些参数
- 设置可选项arguments，其值为gradle传进来的arguments参数。
- 设置APP_SHORT_COMMANDS=false
- 设置LOCAL_SHORT_COMMANDS=false
- 添加-B参数
- 添加-n参数

最终生成的文件大致内容如下：

```
Executable : /Users/lizhangqu/AndroidSDK/ndk-bundle/ndk-build
arguments : 
NDK_PROJECT_PATH=null
APP_BUILD_SCRIPT=path/to/Android.mk
NDK_APPLICATION_MK=path/to/Application.mk
APP_ABI=armeabi
NDK_ALL_ABIS=armeabi
NDK_DEBUG=1
APP_PLATFORM=android-14
NDK_OUT=path/to/moduleDir/build/intermediates/ndkBuild/debug/obj
NDK_LIBS_OUT=path/to/moduleDir/build/intermediates/ndkBuild/debug/lib
APP_CFLAGS+="-fpic -fexceptions -frtti"
APP_CPPFLAGS+="-fpic -fexceptions -frtti"
APP_SHORT_COMMANDS=false
LOCAL_SHORT_COMMANDS=false
-B
-n
jvmArgs : 
```

同理我们也可以直接在命令行调用他们执行

```
/Users/lizhangqu/AndroidSDK/ndk-bundle/ndk-build \
NDK_PROJECT_PATH=null \
APP_BUILD_SCRIPT=path/to/Android.mk \
NDK_APPLICATION_MK=path/to/Application.mk \
APP_ABI=armeabi \
NDK_ALL_ABIS=armeabi \
NDK_DEBUG=1 \
APP_PLATFORM=android-14 \
NDK_OUT=path/to/moduleDir/build/intermediates/ndkBuild/debug/obj \
NDK_LIBS_OUT=path/to/moduleDir/build/intermediates/ndkBuild/debug/lib \
APP_CFLAGS+="-fpic -fexceptions -frtti" \
APP_CPPFLAGS+="-fpic -fexceptions -frtti" \
APP_SHORT_COMMANDS=false \
LOCAL_SHORT_COMMANDS=false \
-B \
-n \
```

其代码调用过程同cmake，最终生成ndkBuild_build_output.txt，该文件内容就是调用ndkBuild_build_command.txt中的命令后控制台输出的内容。

而同cmake不同的是，android_gradle_build.json的文件，不再是由cmake构建系统产生，而是gradle解析ndkBuild_build_command.txt产生的。

其代码大致如下

```
NativeBuildConfigValue buildConfig = new NativeBuildConfigValueBuilder(
            getMakeFile(),
            projectDir)
        .addCommands(
                getBuildCommand(abi, abiPlatformVersion, applicationMk),
                variantName,
                buildOutput,
                isWindows())
        .build();

if (applicationMk.exists()) {
    diagnostic("found application make file %s", applicationMk.getAbsolutePath());
    Preconditions.checkNotNull(buildConfig.buildFiles);
    buildConfig.buildFiles.add(applicationMk);
}

String actualResult = new GsonBuilder()
        .registerTypeAdapter(File.class, new PlainFileGsonTypeAdaptor())
        .setPrettyPrinting()
        .create()
        .toJson(buildConfig);

// Write the captured ndk-build output to JSON file
File expectedJson = ExternalNativeBuildTaskUtils.getOutputJson(getJsonFolder(), abi);
Files.write(actualResult, expectedJson, Charsets.UTF_8);

/**
 * ExternalNativeBuildTaskUtils.getOutputJson
 * Utility function that gets the name of the output JSON for a particular ABI.
 */
@NonNull
public static File getOutputJson(@NonNull File jsonFolder, @NonNull String abi) {
    return new File(getOutputFolder(jsonFolder, abi), "android_gradle_build.json");
}
```

NativeBuildConfigValue的build方法如下，总而言之就是调用各个方法，获取对应的值。

```
/**
 * Builds the {@link NativeBuildConfigValue} from the given information.
 */
@NonNull
public NativeBuildConfigValue build() {
    findLibraryNames();
    findToolchainNames();
    findToolChainCompilers();

    NativeBuildConfigValue config = new NativeBuildConfigValue();
    // Sort by library name so that output is stable
    Collections.sort(outputs, (o1, o2) -> o1.libraryName.compareTo(o2.libraryName));
    config.cleanCommands = generateCleanCommands();
    config.buildFiles = Lists.newArrayList(androidMk);
    config.libraries = generateLibraries();
    config.toolchains = generateToolchains();
    config.cFileExtensions = generateExtensions(cFileExtensions);
    config.cppFileExtensions = generateExtensions(cppFileExtensions);
    return config;
}
```

生成的json文件内容就不贴了，同cmake。