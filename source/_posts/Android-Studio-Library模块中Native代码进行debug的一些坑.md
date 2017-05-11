title: Android Studio Library模块中Native代码进行debug的一些坑
date: 2017-05-11 12:39:14
categories: [NDK]
tags: [NDK, Debug]
---


### 前言

如果项目中存在多个module，那么在application模块中依赖library模块，并且library模块中有native代码的时候，假设你需要debug library模块中的这些native代码，正常情况下，这部分native代码是不能直接被debug的。导致这个问题的根本原因是因为即使在运行application模块的debug构建时，其依赖的library模块并不是以debug构建，而是以release构建。

<!-- more -->

项目结构例子如下图所示

![project.png](project.png)

解决不能debug的方式有两种。

### 1、不进行StripSymbolDebug

Gralde中有一个Task叫transformNativeLibsWithStripDebugSymbolFor${BuildType}，其对应的代码在com.android.build.gradle.internal.transforms.StripDebugSymbolTransform中，翻看代码可以发现如下代码

```
if (excludeMatchers.stream().anyMatch(m -> m.matches(Paths.get(path)))) {
    FileUtils.mkdirs(strippedLib.getParentFile());
    FileUtils.copyFile(input, strippedLib);
} else {
    stripFile(input, strippedLib, abi);
}

private void stripFile(@NonNull File input, @NonNull File output, @Nullable Abi abi)
            throws IOException {
        FileUtils.mkdirs(output.getParentFile());
        if (abi == null) {
            FileUtils.copyFile(input, output);
            return;
        }

        ProcessInfoBuilder builder = new ProcessInfoBuilder();
        builder.setExecutable(stripExecutables.get(abi));
        builder.addArgs("--strip-unneeded");
        builder.addArgs("-o");
        builder.addArgs(output.toString());
        builder.addArgs(input.toString());
        ILogger logger = new LoggerWrapper(project.getLogger());
        ProcessResult result = new GradleProcessExecutor(project).execute(
                builder.createProcess(),
                new LoggedProcessOutputHandler(logger));
        if (result.getExitValue() != 0) {
            logger.warning("Unable to strip library '%s', packaging it as is.",
                    input.getAbsolutePath());
            FileUtils.copyFile(input, output);
        }
    }
```

当满足excludeMatchers中的正则匹配时，该Task执行的是直接拷贝so文件，而不满足时，则执行的是strip操作。

而excludeMatchers是在构造函数中被赋值的

```
@NonNull
private final Set<PathMatcher> excludeMatchers;

public StripDebugSymbolTransform(
        @NonNull Project project,
        @NonNull NdkHandler ndkHandler,
        @NonNull Set<String> excludePattern) {

    this.excludeMatchers = excludePattern.stream()
            .map(StripDebugSymbolTransform::compileGlob)
            .collect(ImmutableCollectors.toImmutableSet());
    checkArgument(ndkHandler.isConfigured());

    for(Abi abi : ndkHandler.getSupportedAbis()) {
        stripExecutables.put(abi, ndkHandler.getStripExecutable(abi));
    }
    this.project = project;
}
```

查看其构造函数被调用的地方

```
TransformManager transformManager = scope.getTransformManager();
GlobalScope globalScope = scope.getGlobalScope();
transformManager.addTransform(
        tasks,
        scope,
        new StripDebugSymbolTransform(
                globalScope.getProject(),
                globalScope.getNdkHandler(),
                globalScope.getExtension().getPackagingOptions().getDoNotStrip()));
```

从上代码可以看到忽略列表是从PackagingOptions中的DoNotStrip传入。

那么问题就好办了，我们只需要在library模块和application模块中加入忽略strip的正则匹配即可，如下

```
android {
    //...
    packagingOptions {
        doNotStrip "*/armeabi/*.so"
        doNotStrip "*/armeabi-v7a/*.so"
        doNotStrip "*/arm64-v8a/*.so"
        doNotStrip "*/x86/*.so"
        doNotStrip "*/x86_64/*.so"
        doNotStrip "*/mips/*.so"
        doNotStrip "*/mips64/*.so"
        //...
    }
}
```

值得注意的是，library模块和application模块中的gradle都需要加入。

但是问题又来了，我们发布到maven的时候，是不需要执行这个的，因此，最好配置一个开关，且这个开关不会被提交到git中去，因此local.properties是最合适的

```
boolean isDebug() {
    boolean ret = false
    try {
        Properties properties = new Properties()
        File file = project.rootProject.file('local.properties')
        if (!file.exists()) {
            return false
        }
        properties.load(file.newDataInputStream())
        String debugStr = properties.getProperty("debug")
        if (debugStr != null && debugStr.length() > 0) {
            ret = debugStr.toBoolean()
        }
    } catch (Throwable throwable) {
        throwable.printStackTrace()
        ret = false
    }
    project.logger.error("[${project.name}]Debug:${ret}")
    return ret
}
```

然后在local.properties中加入debug=true，修改packagingOptions配置为

```
android {
    //...
    if (isDebug()) {
        packagingOptions {
            doNotStrip "*/armeabi/*.so"
            doNotStrip "*/armeabi-v7a/*.so"
            doNotStrip "*/arm64-v8a/*.so"
            doNotStrip "*/x86/*.so"
            doNotStrip "*/x86_64/*.so"
            doNotStrip "*/mips/*.so"
            doNotStrip "*/mips64/*.so"
            //...
        }
    }
}
```

### 2、让Library模块的BuildType随Application模块的BulidType而构建

除了以上的方式，其实还有一种方式，那就是让Library不进行默认的release构建，而是随Application的BuildType而改变，当Application的BuildType为debug时，Library也进行debug构建，当Application的BuildType为release时，Library则进行release构建，要做到这样，需要显示声明一下compile的configuration。

查看Google的相关文档可以发现怎么做：[http://tools.android.com/tech-docs/new-build-system/user-guide#TOC-Library-Publication](http://tools.android.com/tech-docs/new-build-system/user-guide#TOC-Library-Publication)




application模块中的依赖原来是这样的

```
compile project(':library')
```

将其修改为

```
releaseCompile project(path:':library',configuration:'release')
debugCompile project(path:':library',configuration:'debug')
```


然后在library模块中的gradle中加入一行配置，表示不使用默认的

```
android {
    //...
    defaultConfig {
        publishNonDefault true
        //...
    }
}
```

配置完成之后，就可以进行愉快的debug了，但是还没完，对的，需要判断是否是debug，那么以上配置就变成了这样


```
if (isDebug()) {
	releaseCompile project(path:':library',configuration:'release')
	debugCompile project(path:':library',configuration:'debug')
} else {
	compile project(':library')
}

```

```
android {
    //...
    defaultConfig {
        if (isDebug()) {
	        publishNonDefault true
	     }
        //...
    }
}
```

这里之所以加入debug判断，是因为发maven的时候，如果存在publishNonDefault=true，Maven发布插件将把这些额外的variant作为额外的包发布。这意味着它发布到一个maven仓库并不是真正的兼容。我们应该只向一个仓库发布一个单一的 variant。因此发布maven的时候，我们需要关闭这个配置项。

但是为了避免他人不知道这个情况，因此我们最好主动做一次检测，在项目根目录下的build.gradle加入检测代码

```
allprojects.each { project ->
    project.afterEvaluate {
        def uploadArchivesTask = project.tasks.findByName("uploadArchives")
        if (uploadArchivesTask) {
            uploadArchivesTask.doFirst {
                if (isDebug()) {
                    throw new RuntimeException("uploadArchives must disable debug options in local.properties first!")
                }
            }
        }
    }
}
```

一旦运行uploadArchives这个Task的时候，如果是debug，则直接扔异常，不让其发布。