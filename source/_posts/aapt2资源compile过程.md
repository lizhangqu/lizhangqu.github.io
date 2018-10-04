title: aapt2资源compile过程
date: 2017-10-31 09:59:11
categories: [Android]
tags: [Android, aapt2, 资源编译]
---

### 前言

本文基于AOSP Android 8.1分析，Android 9.0 资源proto文件格式发生了变化。

从Android Studio 3.0开始，google默认开启了aapt2作为资源编译的编译器，aapt2的出现，为资源的增量编译提供了支持。当然使用过程中也会遇到一些问题，我们可以通过在**gradle.properties**中配置**android.enableAapt2=false**来关闭aapt2。

<!-- more -->

### 使用方式

aapt2将原先的资源编译打包过程拆分成了两部分，即编译和链接，这样就能很好的提升资源的编译性能，比如只有一个资源文件发送改变时，你只需要重新编译改变的文件，然后将其与其他未改变的资源进行链接即可。而之前的aapt是将所有资源进行merge，merge完后将所有资源进行编译，产生一个**资源ap_**文件，该文件是一个压缩包，这样带来的后果就是即使只改变了一个资源文件，也要进行全量编译。这篇文章主要讲一下aapt2的compile的流程，link的流程比较复杂，后续讲解。


首先来看看其compile命令的使用姿势。

```
aapt2 compile [options] -o arg files...

Options:
 -o arg                                            Output path
 --dir arg                                         Directory to scan for resources
 --pseudo-localize                                 Generate resources for pseudo-locales (en-XA and ar-XB)
 --no-crunch                                       Disables PNG processing
 --legacy                                          Treat errors that used to be valid in AAPT as warnings
 -v                                                Enables verbose logging
 -h                                                Displays this help menu
```

编译过程使用aapt2 compile命令，它有一系列的参数。

**-o**参数指定了编译文件输出的路径，这个参数可以是目录，也可以是文件，取决于输入的资源文件是目录还是文件。假如输入的是目录，则输出的是个zip压缩包，参数值必须是个文件；输入的是单个资源文件，则输出的是一个flat文件，参数值必须是个目录，输出的文件名由aapt2生成。
**--dir**用于指定扫描的资源目录，该参数用于资源的批量编译，不用指定一个个文件单独编译。
**--pseudo-localize**参数在aapt中也有，主要是生成伪本地化信息，如en-XA和ar-XB
**--no-crunch**表示禁用png文件的压缩等处理
**--legacy**表示将aapt中认为是警告的地方作为错误抛出，并终止编译
**-v**参数将开启编译日志的输出
**-h**参数则会输出上面的使用帮助信息

用Android Studio 3.0新建一个新的空项目。我们尝试使用命令行进行资源编译。打开终端，进入当前项目根目录

```
aapt2 compile -o ./build ./app/src/main/res/values/strings.xml
```

以上命令将string.xml进行了编译，最终编译产物位于项目根目录下的build目录中，其文件名为该文件上级目录名_该文件名.arsc.flat，即values_strings.arsc.flat，这是values文件夹下的文件的命名，可以看到xml后缀变成了arsc，这是代码中覆盖文件后缀导致的。我们来看下其他文件，我们编译一个布局文件

```
aapt2 compile -o ./build ./app/src/main/res/layout/activity_main.xml
```
以上命令会编译产生**layout_activity_main.xml.flat**文件，即上级文件目录名_该文件名.flat，这是非values资源的命名方式

看下图片资源编译会产生什么
```
aapt2 compile -o ./build ./app/src/main/res/mipmap-xhdpi/ic_launcher.png 
```
以上命令会编译产生**mipmap-xhdpi_ic_launcher.png.flat**文件，命名方式和layout一样

将上面三个文件连起来一起编译就是
```
aapt2 compile -o ./build ./app/src/main/res/mipmap-xhdpi/ic_launcher.png ./app/src/main/res/layout/activity_main.xml ./app/src/main/res/values/strings.xml 
```

上面是单个文件的编译方式，下面看看直接编译整个目录

```
aapt2 compile -o ./build/res.apk --dir ./app/src/main/res/
```
该命令为产生一个res.apk的文件，该文件是一个zip压缩包，里面包含了编译好的资源文件，如下图所示

![res.png](res.png)

将以上流程总结为一张图

![process.png](process.png)

### flat文件结构解析

那么编译产生的flat文件到底是什么东西呢，不同类型的文件其flat格式是不同的，这里以普通文件举例，即compileFile产生的flat文件(compilePng、compileXml产生的flat文件和compileFile是类似的)，先来看一张结构图

![flat.png](flat.png)

从上图可以看到，flat文件其实就是一种特定的文件格式，文件开头4个字节（32位）表示当前flat文件中的文件个数k，紧跟着8个字节（64位）的数据，表示后面紧跟着的protobuf数据的大小n，接着就是跟着n个字节的protobuf数据，接着是8个字节(64位)的真实数据大小m，紧跟在后面的就是m个字节的真实数据。依次循环k次这种文件结构，最终就是flat文件了。

其中protobuf部分的数据Format.proto的定义如下，非values资源使用的是CompiledFile

```
syntax = "proto2";

option optimize_for = LITE_RUNTIME;

package aapt.pb;

message ConfigDescription {
	optional bytes data = 1;
	optional string product = 2;
}

message StringPool {
	optional bytes data = 1;
}

message CompiledFile {
	message Symbol {
		optional string resource_name = 1;
		optional uint32 line_no = 2;
	}

	optional string resource_name = 1;
	optional ConfigDescription config = 2;
	optional string source_path = 3;
	repeated Symbol exported_symbols = 4;
}

message ResourceTable {
	optional StringPool string_pool = 1;
	optional StringPool source_pool = 2;
	optional StringPool symbol_pool = 3;
	repeated Package packages = 4;
}

message Package {
	optional uint32 package_id = 1;
	optional string package_name = 2;
	repeated Type types = 3;
}

message Type {	
	optional uint32 id = 1;
	optional string name = 2;
	repeated Entry entries = 3;
}

message SymbolStatus {
	enum Visibility {
		Unknown = 0;
		Private = 1;
		Public = 2;
	}
	optional Visibility visibility = 1;
	optional Source source = 2;
	optional string comment = 3;
	optional bool allow_new = 4;
}

message Entry {
	optional uint32 id = 1;
	optional string name = 2;
	optional SymbolStatus symbol_status = 3;
	repeated ConfigValue config_values = 4;
}

message ConfigValue {
	optional ConfigDescription config = 1;
	optional Value value = 2;
}

message Source {
	optional uint32 path_idx = 1;
	optional uint32 line_no = 2;
	optional uint32 col_no = 3;
}

message Reference {
	enum Type {
		Ref = 0;
		Attr = 1;
	}
	optional Type type = 1;
	optional uint32 id = 2;
	optional uint32 symbol_idx = 3;
	optional bool private = 4;
}

message Id {
}

message String {
	optional uint32 idx = 1;
}

message RawString {
	optional uint32 idx = 1;
}

message FileReference {
	optional uint32 path_idx = 1;
}

message Primitive {
	optional uint32 type = 1;
	optional uint32 data = 2;
}

message Attribute {
	message Symbol {
		optional Source source = 1;
		optional string comment = 2;
		optional Reference name = 3;
		optional uint32 value = 4;
	}
	optional uint32 format_flags = 1;
	optional int32 min_int = 2;
	optional int32 max_int = 3;
	repeated Symbol symbols = 4;
}

message Style {
	message Entry {
		optional Source source = 1;
		optional string comment = 2;
		optional Reference key = 3;
		optional Item item = 4;
	}

	optional Reference parent = 1;
	optional Source parent_source = 2;
	repeated Entry entries = 3;
}

message Styleable {
	message Entry {
		optional Source source = 1;
		optional string comment = 2;
		optional Reference attr = 3;
	}
	repeated Entry entries = 1;
}

message Array {
	message Entry {
		optional Source source = 1;
		optional string comment = 2;
		optional Item item = 3;
	}
	repeated Entry entries = 1;
}

message Plural {
	enum Arity {
		Zero = 0;
		One = 1;
		Two = 2;
		Few = 3;
		Many = 4;
		Other = 5;
	}
		
	message Entry {
		optional Source source = 1;
		optional string comment = 2;
		optional Arity arity = 3;
		optional Item item = 4;
	}
	repeated Entry entries = 1;
}

message Item {
	optional Reference ref = 1;
	optional String str = 2;
	optional RawString raw_str = 3;
	optional FileReference file = 4;
	optional Id id = 5;
	optional Primitive prim = 6;
}

message CompoundValue {
	optional Attribute attr = 1;
	optional Style style = 2;
	optional Styleable styleable = 3;
	optional Array array = 4;
	optional Plural plural = 5;
}

message Value {
	optional Source source = 1;
	optional string comment = 2;
	optional bool weak = 3;
	
	optional Item item = 4;
	optional CompoundValue compound_value = 5;	
}

```

以上是非values资源产生的flat文件的文件格式，**而values类型的资源，其实是以上数据格式的阉割版，即只有protobuf部分的数据结构，其结构为上面proto格式部分的ResourceTable部分**

值得注意的是还有一个4字节对齐的问题，有兴趣可以查看源码。



### gradle中compile流程

gradle中主要由OutOfProcessAaptV2和AaptV2CommandBuilder类承载aapt2的执行，关键函数如下

```

    @Nullable
    @Override
    protected CompileInvocation makeCompileProcessBuilder(@NonNull CompileResourceRequest request)
            throws AaptException {
        Preconditions.checkArgument(request.getInput().isFile(), "!file.isFile()");
        Preconditions.checkArgument(request.getOutput().isDirectory(), "!output.isDirectory()");

        return new CompileInvocation(
                new ProcessInfoBuilder()
                        .setExecutable(getAapt2ExecutablePath())
                        .addArgs("compile")
                        .addArgs(AaptV2CommandBuilder.makeCompile(request)),
                new File(
                        request.getOutput(),
                        Aapt2RenamingConventions.compilationRename(request.getInput())));
    }

    public static ImmutableList<String> makeCompile(@NonNull CompileResourceRequest request) {
        ImmutableList.Builder<String> parameters = new ImmutableList.Builder();

        if (request.isPseudoLocalize()) {
            parameters.add("--pseudo-localize");
        }

        if (!request.isPngCrunching()) {
            // Only pass --no-crunch for png files and not for 9-patch files as that breaks them.
            String lowerName = request.getInput().getPath().toLowerCase(Locale.US);
            if (lowerName.endsWith(SdkConstants.DOT_PNG)
                    && !lowerName.endsWith(SdkConstants.DOT_9PNG)) {
                parameters.add("--no-crunch");
            }
        }

        parameters.add("--legacy");
        parameters.add("-o", request.getOutput().getAbsolutePath());
        parameters.add(request.getInput().getAbsolutePath());

        return parameters.build();
    }

```

很简单，就是简单的命令拼接，和上面说的是完全一样的。

### 总结

开启了aapt2后，资源的增量编译会加速编译速度，但是有些场景aapt2并不是很合适，因此必要的情况下，建议关闭aapt2，比如jenkins上构建时，我们并不需要增量编译，因此可以关闭，可以通过gradle参数达到关闭的效果，命令如下

```
gradle assembleRelease -Pandroid.enableAapt2=false
```

简单总结了几种不适合使用aapt2的场景
 
  - 插件化和热修复中，需要使用public.xml的场景
  - 构建过程，需要动态增删改资源的场景，如删除一部分线上不应该出现的资源