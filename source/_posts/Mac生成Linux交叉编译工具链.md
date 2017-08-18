title: Mac生成Linux交叉编译工具链
date: 2017-08-18 11:41:58
categories: [Mac]
tags: [Mac, Linux, 交叉编译]
---

需要在Mac上编译出Linux服务器上可用的动态库，使用crosstool-ng生成交叉编译工具链

<!-- more -->

### 大小写敏感的磁盘


#### 创建

```
hdiutil create -volname "crosstool-ng" -type SPARSE -fs 'Case-sensitive Journaled HFS+' -size 20g crosstool-ng.dmg
```

#### 挂载

```
hdiutil attach crosstool-ng.dmg.sparseimage -mountpoint /Volumes/crosstool-ng
```

#### 卸载（使用完后进行卸载）

```
hdiutil detach /Volumes/crosstool-ng
```

### 安装依赖

```
brew install autoconf binutils gawk gmp gnu-sed help2man mpfr openssl pcre readline wget xz
```

如果后续报什么错，提示没有什么包继续安装对应包即可。


### 编译crosstool-ng

crosstool-ng的文档地址在 [http://crosstool-ng.github.io/docs/](http://crosstool-ng.github.io/docs/)

github地址在 [https://github.com/crosstool-ng/crosstool-ng](https://github.com/crosstool-ng/crosstool-ng)

#### 下载源码

```
wget http://crosstool-ng.org/download/crosstool-ng/crosstool-ng-1.23.0.tar.bz2
```

#### 解压

```
tar -jxvf crosstool-ng-1.23.0.tar.bz2
```

#### 进入源码目录

```
cd crosstool-ng-1.23.0
```

#### 执行bootstrap脚本（可选，如果该文件存在的话需要执行，不存在该文件则跳过此步骤）

```
./bootstrap
```

#### 执行configure

```
./configure
```

#### 执行编译

```
make -j4
```

#### 执行安装

```
make install
```

之后就可以直接使用ct-ng命令了

### 配置交叉编译工具链

创建工作目录并进入

```
mkdir workdir
cd workdir
```

拷贝配置文件。这里基于源码目录crosstool-ng-1.23.0/sample/x86_64-unknown-linux-gnu下的config进行自定义

```
cp path/to/crosstool-ng-1.23.0/sample/x86_64-unknown-linux-gnu/crosstool.config .config
```

配置配置文件，需要将一些目录指向我们最开始创建的大小写敏感的磁盘

```
ct-ng menuconfig
```

选择Paths and misc options，找到Paths，下面有三个路径需要修改

修改Local tarballs dictory指向大小写敏感的磁盘，如

```
/Volumes/crosstool-ng/src
```

修改Working dictory指向大小写敏感的磁盘，如

```
/Volumes/crosstool-ng/.build
```

修改x-tools指向大小写敏感的磁盘，如

```
CT_PREFIX:-/Volumes/crosstool-ng/x-tools}/${CT_HOST:+HOST-${CT_HOST}/}${CT_TARGET}
```

因为需要用到从历史构建断点继续构建的功能，将Paths and misc options->crosstool-NG behavior选项下的Debug crosstool-NG勾选，然后继续勾选Save intermediate steps

修改完成后保存然后退出

#### 修改binutils版本

因为我们拷贝的config使用的是2.28的binutils，而gnu的ftp上不存在该版本对应xy后缀的文件，所以需要修改版本为2.29，而2.29版本是存在xy后缀的文件的

还是一样进入menuconfig，找到Binary utilities->binutils version，修改版本号为2.29，但是发现这里没有2.29的选项，因此需要修改源码，然后重新执行编译安装步骤

打开源码crosstool-ng-1.23.0/config/binutils/binutils.in文件，找到如下代码

```
config BINUTILS_V_2_28
    bool
    prompt "2.28"
    select BINUTILS_2_27_or_later
```

在前面加入

```
config BINUTILS_V_2_29
    bool
    prompt "2.29"
    select BINUTILS_2_28_or_later
```

然后往下找到如下代码

```
# CT_INSERT_VERSION_STRING_BELOW
default "2.28" if BINUTILS_V_2_28
default "2.27" if BINUTILS_V_2_27
default "2.26" if BINUTILS_V_2_26
default "2.25.1" if BINUTILS_V_2_25_1
default "linaro-2.25.0-2015.01-2" if BINUTILS_LINARO_V_2_25
default "linaro-2.24.0-2014.11-2" if BINUTILS_LINARO_V_2_24
default "2.24" if BINUTILS_V_2_24
default "linaro-2.23.2-2013.10-4" if BINUTILS_LINARO_V_2_23_2
default "2.23.2" if BINUTILS_V_2_23_2
```

在前面加入下面的代码

```
default "2.29" if BINUTILS_V_2_29
```

然后重新执行./configure、make -j4、make install等命令重新安装，然后再次进入menuconfig，会发现可以选择2.29了

### 生成交叉编译工具链

在workdir下执行命令构建

```
ct-ng build
```

然后会下载一些zip文件到/Volumes/crosstool-ng/.build/tarballs下，文件有

```
binutils-2.29.tar.xz
expat-2.2.0.tar.bz2
gcc-6.3.0.tar.bz2
gdb-7.12.1.tar.xz
gettext-0.19.8.1.tar.xz
glibc-2.25.tar.xz
gmp-6.1.2.tar.xz
isl-0.16.1.tar.xz
libiconv-1.15.tar.gz
linux-4.10.8.tar.xz
m4-1.4.18.tar.xz
mpc-1.0.3.tar.gz
mpfr-3.1.5.tar.xz
ncurses-6.0.tar.gz
```

如果你觉得下载慢，可以手动下载这些文件，将其放入/Volumes/crosstool-ng/.build/tarballs，注意名字保持和上面一样。

之后会执行解压，构建，安装等操作，大约需要2-3小时后编译完成。

因为开启了debug相关的功能，如果中断了构建，可以随时从中断的地方继续构建，只需要找到对应的step即可，step可以从控制台的输出log中找到。

假设log中出现了如下字样，需要从该步骤恢复

```
Saving state to restart at step 'companion_tools_for_build'...
```

只需要执行下面的代码即可

```
ct-ng companion_tools_for_build+
```

或者

```
ct-ng build RESTART=companion_tools_for_build
```

### 编写cmake toolchain交叉编译工具链文件

关于cmake toolchain的编写，见cmake文档 [cross-compiling](https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html#cross-compiling)

创建linux-x86_64.toolchain.cmake文件，加入如下内容

```
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(LINUX_TOOLCHAIN_NAME x86_64-unknown-linux-gnu-)
set(LINUX_TOOLCHAIN_ROOT /Volumes/crosstool-ng/x-tools/x86_64-unknown-linux-gnu)
set(CMAKE_SYSROOT ${LINUX_TOOLCHAIN_ROOT}/x86_64-unknown-linux-gnu/sysroot)

set(CMAKE_C_COMPILER   ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}gcc)
set(CMAKE_CXX_COMPILER ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}g++)
set(CMAKE_AR           ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}ar CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB       ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}ranlib CACHE FILEPATH "Ranlib")

set(CMAKE_ASM_COMPILER ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}as)
set(CMAKE_LINKER       ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}ld)
set(CMAKE_NM           ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}nm)
set(CMAKE_OBJCOPY      ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}objcopy)
set(CMAKE_OBJDUMP      ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}objdump)
set(CMAKE_STRIP        ${LINUX_TOOLCHAIN_ROOT}/bin/${LINUX_TOOLCHAIN_NAME}strip)

message(STATUS "CMAKE_SYSROOT = ${CMAKE_SYSROOT}")
message(STATUS "CMAKE_C_COMPILER = ${CMAKE_C_COMPILER}")
message(STATUS "CMAKE_CXX_COMPILER = ${CMAKE_CXX_COMPILER}")
message(STATUS "CMAKE_AR = ${CMAKE_AR}")
message(STATUS "CMAKE_RANLIB = ${CMAKE_RANLIB}")
message(STATUS "CMAKE_ASM_COMPILER = ${CMAKE_ASM_COMPILER}")
message(STATUS "CMAKE_LINKER = ${CMAKE_LINKER}")
message(STATUS "CMAKE_NM = ${CMAKE_NM}")
message(STATUS "CMAKE_OBJCOPY = ${CMAKE_OBJCOPY}")
message(STATUS "CMAKE_OBJDUMP = ${CMAKE_OBJDUMP}")
message(STATUS "CMAKE_STRIP = ${CMAKE_STRIP}")

# Set or retrieve the cached flags.
# This is necessary in case the user sets/changes flags in subsequent
# configures. If we included the flags in here, they would get
# overwritten.

set(CMAKE_C_FLAGS ""
	CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_CXX_FLAGS ""
	CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_ASM_FLAGS ""
	CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_C_FLAGS_DEBUG ""
	CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_CXX_FLAGS_DEBUG ""
	CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_ASM_FLAGS_DEBUG ""
	CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_C_FLAGS_RELEASE ""
	CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_CXX_FLAGS_RELEASE ""
	CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_ASM_FLAGS_RELEASE ""
	CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_MODULE_LINKER_FLAGS ""
	CACHE STRING "Flags used by the linker during the creation of modules.")
set(CMAKE_SHARED_LINKER_FLAGS ""
	CACHE STRING "Flags used by the linker during the creation of dll's.")
set(CMAKE_EXE_LINKER_FLAGS ""
	CACHE STRING "Flags used by the linker.")

set(CMAKE_C_FLAGS             "${CMAKE_C_FLAGS}")
set(CMAKE_CXX_FLAGS           "${CMAKE_CXX_FLAGS}")
set(CMAKE_ASM_FLAGS           "${CMAKE_ASM_FLAGS}")
set(CMAKE_C_FLAGS_DEBUG       "${CMAKE_C_FLAGS_DEBUG}")
set(CMAKE_CXX_FLAGS_DEBUG     "${CMAKE_CXX_FLAGS_DEBUG}")
set(CMAKE_ASM_FLAGS_DEBUG     "${CMAKE_ASM_FLAGS_DEBUG}")
set(CMAKE_C_FLAGS_RELEASE     "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_RELEASE   "${CMAKE_CXX_FLAGS_RELEASE}")
set(CMAKE_ASM_FLAGS_RELEASE   "${CMAKE_ASM_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS    "${CMAKE_EXE_LINKER_FLAGS}")

#set(CMAKE_CXX_FLAGS           "${CMAKE_CXX_FLAGS} -Wno-unknown-pragmas")
# or 
#add_definitions("-Wno-unknown-pragmas")


set(CMAKE_FIND_ROOT_PATH ${LINUX_TOOLCHAIN_ROOT})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLYONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

#make VERVOSE=1 to output the log
```

值得注意的是CMAKE_AR和CMAKE_RANLIB后面加了CACHE FILEPATH，这是必须的，不然可能会出错。

### 交叉编译

通过CMAKE_TOOLCHAIN_FILE参数指定toolchain文件

```
cmake -DCMAKE_TOOLCHAIN_FILE=../linux-x86_64.toolchain.cmake ..
```

然后执行make，执行make过程中如果发生错误，可以设置VERVOSE=1将一些信息输出，便于调试

```
make VERVOSE=1
```

### 测试

将编译出来的动态库拷到linux上去测试，看是否可以正常使用，如果出现了类似 libstdc++.so.6: version `CXXABI_ARM_1.3.8' not found 的错误，是因为生成的交叉编译工具链和服务器环境的gcc版本不一致导致的，要么修改交叉编译工具链的gcc版本和服务器上的gcc版本一样，要么修改服务器上的gcc版本和交叉编译工具链的gcc版本一样，无论哪种方式都可以。


### 关于jni

因为用到了jni，需要用到相关的头文件，而crosstool-ng其实是可以配置java的，但是测试下来发现宿主机Mac需要用到gcj，找了一大圈发现gcj老早已经从gcc中被移除了，如果需要用，则需要自己编译，实在麻烦。所以干脆简单点，直接拷贝头文件就可以解决问题，有两种解决方法

 1. 到服务器的JAVA_HOME目录，将include文件拷贝下来直接用
 2. 下载linux的jdk压缩包，直接提取出来用

编译的时候指定jni的头文件目录即可，这里将include文件夹中的内容放在/Volumes/crosstool-ng/java-linux下的include目录

### 关于gradle

gradle里用cmake编译c/c++代码，需要自己写gradle脚本，这里提供一个自己写的脚本

```
apply plugin: JNIPlugin

class JNIPlugin implements Plugin<Project> {
    static def currentOS() {
        final String p = System.getProperty("os.name").toLowerCase();
        if (p.contains("linux")) {
            return "linux"
        } else if (p.contains("os x") || p.contains("darwin")) {
            return "darwin"
        } else if (p.contains("windows")) {
            return "windows"
        } else {
            return p.replaceAll("\\s", "")
        }
    }

    static String currentArchitecture() {
        final String arch = System.getProperty("os.arch").toLowerCase()
        return (arch.equals("amd64")) ? "x86_64" : arch
    }

    void apply(Project project) {
        project.afterEvaluate {

//            def osList = ["darwin", "linux"]
//            def architectureList = ["x86_64"]

            //当前环境为mac
            def osList = ["${currentOS()}", "linux"]
            def architectureList = ["${currentArchitecture()}"]
            def javaHomeList = [
                    "${currentOS()}": "${System.getenv('JAVA_HOME')}",
                    "linux"         : "/Volumes/crosstool-ng/java-linux"
            ]

            osList.each { os ->
                architectureList.each { architecture ->
                    def javaHome = javaHomeList.get(os)

                    File staticWorkingDir = project.file("jni/demo-static/${os}-${architecture}")
                    File dynamicWorkingDir = project.file("jni/demo-dynamic/${os}-${architecture}")

                    def demoStaticCleanTask = project.task("cleanDemoStaticFor${os.capitalize()}${architecture.capitalize()}")
                    demoStaticCleanTask.setGroup("jni")
                    demoStaticCleanTask.doLast {
                        project.println "delete demo static cmake files ${demoStaticCleanTask}"
                        GFileUtils.deleteDirectory(demoStaticCleanTask)
                    }

                    def demoDynamicCleanTask = project.task("cleanDemoDynamicFor${os.capitalize()}${architecture.capitalize()}")
                    demoDynamicCleanTask.setGroup("jni")
                    demoDynamicCleanTask.doLast {
                        project.println "delete demo dynamic cmake files ${dynamicWorkingDir}"
                        GFileUtils.deleteDirectory(dynamicWorkingDir)
                    }

                    def cleanTask = project.tasks.findByName("clean")
                    if (cleanTask) {
                        cleanTask.dependsOn demoStaticCleanTask
                        cleanTask.dependsOn demoDynamicCleanTask
                    }

                    def demoStaticTask = project.task("demoStaticFor${os.capitalize()}${architecture.capitalize()}")
                    demoStaticTask.setGroup("jni")

                    demoStaticTask.doLast {

                        File staticLibrary = new File(staticWorkingDir, "/install/lib/libdemostatic.a")
                        if (!staticLibrary.exists()) {
                            project.println "staticLibrary not exist."
                            GFileUtils.deleteDirectory(staticWorkingDir)
                            GFileUtils.mkdirs(staticWorkingDir)

                            //generate cmake files
                            project.exec(new Action<ExecSpec>() {
                                @Override
                                void execute(ExecSpec execSpec) {
                                    execSpec.workingDir staticWorkingDir
                                    execSpec.executable "cmake"
                                    if (os == "linux" && currentOS() != "linux") {
                                        execSpec.args "-DCMAKE_TOOLCHAIN_FILE=${project.file('jni/linux-x86_64.toolchain.cmake')}"
                                    }
                                    execSpec.args("..")
                                }
                            })

                            //clean
                            project.exec(new Action<ExecSpec>() {
                                @Override
                                void execute(ExecSpec execSpec) {
                                    execSpec.workingDir staticWorkingDir
                                    execSpec.executable "make"
                                    execSpec.args("clean")
                                }
                            })
                        }

                        //make
                        project.exec(new Action<ExecSpec>() {
                            @Override
                            void execute(ExecSpec execSpec) {
                                execSpec.workingDir staticWorkingDir
                                execSpec.executable "make"
                                execSpec.args("-j4")
                            }
                        })

                        //install
                        project.exec(new Action<ExecSpec>() {
                            @Override
                            void execute(ExecSpec execSpec) {
                                execSpec.workingDir staticWorkingDir
                                execSpec.executable "make"
                                execSpec.args("install")
                            }
                        })
                    }


                    def demoDynamicTask = project.task("demoDynamicFor${os.capitalize()}${architecture.capitalize()}")
                    demoDynamicTask.setGroup("jni")
                    demoDynamicTask.dependsOn demoStaticTask
                    demoDynamicTask.doLast {

                        File dynamicLibraryDir = new File(dynamicWorkingDir, "/install/lib")
                        File demoStaticInstallDir = new File(staticWorkingDir, "/install")
                        String demoVersion = "0.0.1"

                        File[] dynamicLibrary = dynamicLibraryDir.listFiles(new FileFilter() {
                            @Override
                            boolean accept(File pathname) {
                                return pathname.isFile() && pathname.getName().startsWith("lib")
                            }
                        })
                        if (!dynamicLibraryDir.exists() || dynamicLibrary == null || dynamicLibrary.length == 0) {
                            project.println "dynamicLibrary not exist."
                            GFileUtils.deleteDirectory(dynamicWorkingDir)
                            GFileUtils.mkdirs(dynamicWorkingDir)

                            //generate cmake files
                            project.exec(new Action<ExecSpec>() {
                                @Override
                                void execute(ExecSpec execSpec) {
                                    execSpec.workingDir dynamicWorkingDir
                                    execSpec.executable "cmake"
                                    execSpec.args("-DDEMO_INSTALL_PATH=${demoStaticInstallDir.absolutePath}")
                                    execSpec.args("-DVERSION=${demoVersion}")
                                    execSpec.args("-DJAVA_INCLUDE=${javaHome}/include")
                                    execSpec.args("-DJAVA_OS_INCLUDE=${javaHome}/include/${os}")
                                    if (os == "linux" && currentOS() != "linux") {
                                        execSpec.args "-DCMAKE_TOOLCHAIN_FILE=${project.file('jni/linux-x86_64.toolchain.cmake')}"
                                    }
                                    execSpec.args("..")
                                }
                            })

                            //clean
                            project.exec(new Action<ExecSpec>() {
                                @Override
                                void execute(ExecSpec execSpec) {
                                    execSpec.workingDir dynamicWorkingDir
                                    execSpec.executable "make"
                                    execSpec.args("clean")
                                }
                            })
                        }

                        //make
                        project.exec(new Action<ExecSpec>() {
                            @Override
                            void execute(ExecSpec execSpec) {
                                execSpec.workingDir dynamicWorkingDir
                                execSpec.executable "make"
                                execSpec.args("VERBOSE=1")
                                execSpec.args("-j4")
                            }
                        })

                        //install
                        project.exec(new Action<ExecSpec>() {
                            @Override
                            void execute(ExecSpec execSpec) {
                                execSpec.workingDir dynamicWorkingDir
                                execSpec.executable "make"
                                execSpec.args("install")
                            }
                        })
                    }

                    def compileJavaTask = project.tasks.findByName("compileJava")
                    if (compileJavaTask) {
                        compileJavaTask.dependsOn demoStaticTask
                        compileJavaTask.dependsOn demoDynamicTask
                    }
                }
            }
        }
    }
}

```

当然打包jar的时候，还需要将动态库打到jar包里

```
apply plugin: 'java'
sourceCompatibility = 1.8

static def currentOS() {
    final String p = System.getProperty("os.name").toLowerCase()
    if (p.contains("linux")) {
        return "linux"
    } else if (p.contains("os x") || p.contains("darwin")) {
        return "darwin"
    } else if (p.contains("windows")) {
        return "windows"
    } else {
        return p.replaceAll("\\s", "")
    }
}

static def currentArchitecture() {
    final String arch = System.getProperty("os.arch").toLowerCase()
    return (arch.equals("amd64")) ? "x86_64" : arch
}

jar {
    //def osList = ["darwin", "linux"]
    //def architectureList = ["x86_64"]
    def osList = ["${currentOS()}", "linux"]
    def architectureList = ["${currentArchitecture()}"]

    osList.each { os ->
        architectureList.each { architecture ->
            //copy shared library to classpath when assemble a jar
            from(project.file("jni/demoDynamic/${os}-${architecture}/install/lib")) {
                into "com/lizhangqu/lib/dynamic/${os}-${architecture}"
            }
        }
    }

}

```

cmake中需要指定安装目录

```
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/install" CACHE PATH "Installation Directory")
endif()
message(STATUS "CMAKE_INSTALL_PREFIX = ${CMAKE_INSTALL_PREFIX}")
```

cmake 中install动态库

```
install(TARGETS demodynamic LIBRARY DESTINATION lib)
```


### 关于java加载

参考tensorflow的动态库加载方式，代码如下

```
final class NativeLibrary {
    private static final boolean DEBUG = true;
    private static final String PACKAGENAME = "com/lizhangqu/lib/dynamic";
    private static final String LIBNAME = "demodynamic";

    public static void load() {
        if (isLoaded() || tryLoadLibrary()) {
            // Either:
            // (1) The native library has already been statically loaded, OR
            // (2) The required native code has been statically linked (through a custom launcher), OR
            // (3) The native code is part of another library (such as an an application-level libraryh)
            // that has already been loaded.
            //
            // Doesn't matter how, but it seems the native code is loaded, so nothing else to do.
            return;
        }
        // Native code is not present, perhaps it has been packaged into the .jar file containing this.
        final String resourceName = makeResourceName();
        log("resourceName: " + resourceName);
        InputStream resource =
                NativeLibrary.class.getClassLoader().getResourceAsStream(resourceName);

        //retry
        if (resource == null) {
            String abiName = makeABILibName();
            log("abiName: " + abiName);
            resource = NativeLibrary.class.getResourceAsStream(abiName);
        }

        if (resource == null) {
            throw new UnsatisfiedLinkError(
                    String.format(
                            "Cannot find bridge native library for OS: %s, architecture: %s. ",
                            os(), architecture()));
        }
        try {
            System.load(extractResource(resource));
        } catch (IOException e) {
            throw new UnsatisfiedLinkError(
                    String.format(
                            "Unable to extract native library into a temporary file (%s)", e.toString()));
        }
    }

    private static boolean tryLoadLibrary() {
        try {
            System.loadLibrary(LIBNAME);
            return true;
        } catch (UnsatisfiedLinkError e) {
            log("tryLoadLibraryFailed: " + e.getMessage());
            return false;
        }
    }

    private static boolean isLoaded() {
        try {
            //提供getVersion方法用于测试是否加载成功
            String version = DemoDynamic.getVersion();
            log("version: " + version);
            log("isLoaded: true");
            return true;
        } catch (UnsatisfiedLinkError e) {
            return false;
        }
    }

    private static String extractResource(InputStream resource) throws IOException {
        final String sampleFilename = System.mapLibraryName(LIBNAME);
        final int dot = sampleFilename.indexOf(".");
        final String prefix = (dot < 0) ? sampleFilename : sampleFilename.substring(0, dot);
        final String suffix = (dot < 0) ? null : sampleFilename.substring(dot);

        final File dst = File.createTempFile(prefix, suffix);
        final String dstPath = dst.getAbsolutePath();
        dst.deleteOnExit();
        log("extracting native library to: " + dstPath);
        final long nbytes = copy(resource, dst);
        log(String.format("copied %d bytes to %s", nbytes, dstPath));
        return dstPath;
    }

    private static String os() {
        final String p = System.getProperty("os.name").toLowerCase();
        if (p.contains("linux")) {
            return "linux";
        } else if (p.contains("os x") || p.contains("darwin")) {
            return "darwin";
        } else if (p.contains("windows")) {
            return "windows";
        } else {
            return p.replaceAll("\\s", "");
        }
    }

    private static String architecture() {
        final String arch = System.getProperty("os.arch").toLowerCase();
        return (arch.equals("amd64")) ? "x86_64" : arch;
    }

    private static void log(String msg) {
        if (DEBUG) {
            System.err.println("com.lizhangqu.lib.dynamic.NativeLibrary: " + msg);
        }
    }

    private static String makeResourceName() {
        return PACKAGENAME
                + String.format("/%s-%s/", os(), architecture())
                + System.mapLibraryName(LIBNAME);
    }

    private static String makeABILibName() {
        return String.format("%s-%s/", os(), architecture())
                + System.mapLibraryName(LIBNAME);
    }

    private static long copy(InputStream src, File dstFile) throws IOException {
        FileOutputStream dst = new FileOutputStream(dstFile);
        try {
            byte[] buffer = new byte[1 << 20]; // 1MB
            long ret = 0;
            int n = 0;
            while ((n = src.read(buffer)) >= 0) {
                dst.write(buffer, 0, n);
                ret += n;
            }
            return ret;
        } finally {
            dst.close();
            src.close();
        }
    }
}

```
