title: art dex2oat加载加速浅析
date: 2018-12-30 20:56:21
categories: [Android]
tags: [Android, ART, dex2oat]
---

### 前言

手淘的插件化框架Atlas在ART上首次启动的时候，会通过禁用dex2oat来达到插件迅速启动的目的。之后后台进行dex2oat，下次启动如果dex2oat完成了则启用dex2oat，如果没有完成则继续禁用dex2oat。但是这部分代码淘宝并没有开源。且由于Atlas后续持续维护的可能性极低，加上Android 9.0上禁用失败及64位动态库在部分系统上禁用会发生crash，对于核心技术我们必须能掌握在自己手中。此文结合逆向与正向的角度来分析Atlas是通过什么手段达到禁用dex2oat的，以及如何自己实现代码达到禁用的目的。

<!-- more -->

### 逆向日志分析

由于手淘Atlas这部分代码是闭源的，因此我们无法正向分析其原理。所以我们可以从逆向的角度进行分析。逆向分析的关键一步就是懂得看控制台日志，从日志中入手进行分析。

通过在Android 5.0，Android 6.0，Android 7.0，Android 8.0 和 Android 9.0上运行插件化的App，我们发现，控制台会输出一部分关键性的日志。内容如下

![dex2oat-log.png](dex2oat-log.png)

通过在AOSP中查找关键日志 Generation of oat file .... not attempt because dex2oat is disabled 即可继续发现猫腻。最终我们会发现这部分信息出现在了class_linker.cc类或者oat_file_manager.cc类中。

### 正向源码分析

有了以上基础，我们尝试从源码角度进行正向分析。

在Java层我们加载一个Dex是通过DexFile.loadDex()方法进行加载。此方法最终会走到native方法 openDexFileNative，Android 5.0的源码如下
 - [android-5.0.0_r7/runtime/native/dalvik_system_DexFile.cc#101](https://android.googlesource.com/platform/art/+/android-5.0.0_r7/runtime/native/dalvik_system_DexFile.cc#101)

```
static jlong DexFile_openDexFileNative(JNIEnv* env, jclass, jstring javaSourceName, jstring javaOutputName, jint) {
  ScopedUtfChars sourceName(env, javaSourceName);
  if (sourceName.c_str() == NULL) {
    return 0;
  }
  NullableScopedUtfChars outputName(env, javaOutputName);
  if (env->ExceptionCheck()) {
    return 0;
  }
  ClassLinker* linker = Runtime::Current()->GetClassLinker();
  std::unique_ptr<std::vector<const DexFile*>> dex_files(new std::vector<const DexFile*>());
  std::vector<std::string> error_msgs;
  //关键调用在这里
  bool success = linker->OpenDexFilesFromOat(sourceName.c_str(), outputName.c_str(), &error_msgs,
                                             dex_files.get());
  if (success || !dex_files->empty()) {
    // In the case of non-success, we have not found or could not generate the oat file.
    // But we may still have found a dex file that we can use.
    return static_cast<jlong>(reinterpret_cast<uintptr_t>(dex_files.release()));
  } else {
    // The vector should be empty after a failed loading attempt.
    DCHECK_EQ(0U, dex_files->size());
    ScopedObjectAccess soa(env);
    CHECK(!error_msgs.empty());
    // The most important message is at the end. So set up nesting by going forward, which will
    // wrap the existing exception as a cause for the following one.
    auto it = error_msgs.begin();
    auto itEnd = error_msgs.end();
    for ( ; it != itEnd; ++it) {
      ThrowWrappedIOException("%s", it->c_str());
    }
    return 0;
  }
}
```

最终会调用到ClassLinker中的OpenDexFilesFromOat方法

对应代码过长，这里不贴了，见 
 - [android-5.0.0_r7/runtime/class_linker.cc#811](https://android.googlesource.com/platform/art/+/android-5.0.0_r7/runtime/class_linker.cc#811)

OpenDexFilesFromOat函数主要做了如下几步
 - 1、检测我们是否已经有一个打开的oat文件
 - 2、如果没有已经打开的oat文件，则从磁盘上检测是否有一个已经生成的oat文件
 - 3、如果磁盘上有一个生成的oat文件，则检测该oat文件是否过期了以及是否包含了我们所有的dex文件
 - 4、如果以上都不满足，则会重新生成

首次打开时，1-3步必然是不满足的，最终会走到第四个逻辑，这一步有一个关键性的代码直接决定了生成oat文件是否生成成功

```
if (Runtime::Current()->IsDex2OatEnabled() && has_flock && scoped_flock.HasFile()) {
   // Create the oat file.
   open_oat_file.reset(CreateOatFileForDexLocation(dex_location, scoped_flock.GetFile()->Fd(),
                                                   oat_location, error_msgs));
}
```

核心函数Runtime::Current()->IsDex2OatEnabled()，判断dex2oat是否开启，如果开启，则创建oat文件并进行更新。

以上是Android 5.0的源码，Android 6.0-Android 9.0会有所差异。DexFile_openDexFileNative最终会调用到runtime->GetOatFileManager().OpenDexFilesFromOat()，继续会调用到OatFileAssistant类中的MakeUpToDate函数，一直调用到GenerateOatFile(Androiod 6.0-7.0)或GenerateOatFileNoChecks(Android 8.0-9.0)等类型函数，相关代码见如下链接。
 - [android-9.0.0_r18/runtime/native/dalvik_system_DexFile.cc#267](https://android.googlesource.com/platform/art/+/android-9.0.0_r18/runtime/native/dalvik_system_DexFile.cc#267)
 - [android-9.0.0_r18/runtime/oat_file_manager.cc#394](https://android.googlesource.com/platform/art/+/android-9.0.0_r18/runtime/oat_file_manager.cc#394)
 - [android-7.0.0_r1/runtime/oat_file_assistant.cc#206 (Androiod 6.0-7.0)](https://android.googlesource.com/platform/art/+/android-7.0.0_r1/runtime/oat_file_assistant.cc#206)     
 - [android-9.0.0_r18/runtime/oat_file_assistant.cc#251 (Android 8.0-9.0)](https://android.googlesource.com/platform/art/+/android-9.0.0_r18/runtime/oat_file_assistant.cc#251 )   

最终我们也会发现一段关键性的代码，如下

```
Runtime* runtime = Runtime::Current();
if (!runtime->IsDex2OatEnabled()) {
    *error_msg = "Generation of oat file for dex location " + dex_location_
                 + " not attempted because dex2oat is disabled.";
    return kUpdateNotAttempted;
}
```

可以看到，我们已经看到了我们逆向日志分析时，从控制台看到的日志内容，Generation of oat file....not attempted because dex2oat is disabled，这说明我们源码找对了。

通过以上分析，我们发现Android 5.0-Android 9.0最终都会走到Runtime::Current()->IsDex2OatEnabled()函数，如果dex2oat没有开启，则不会进行后续oat文件生成的操作，而是直接return返回。所以结论已经很明确了，就是通过设置该函数的返回值为false，达到禁用dex2oat的目的。

通过查看Runtime类的代码，可以发现IsDex2OatEnabled其实很简单，就是返回了一个dex2oat_enabled_成员变量与另一个image_dex2oat_enabled_成员变量。源码见：
 - [android-5.0.0_r7/runtime/runtime.h#109](https://android.googlesource.com/platform/art/+/android-5.0.0_r7/runtime/runtime.h#109)
 - [android-9.0.0_r18/runtime/runtime.h#145](https://android.googlesource.com/platform/art/+/android-9.0.0_r18/runtime/runtime.h#145)


```
bool IsDex2OatEnabled() const {
    return dex2oat_enabled_ && IsImageDex2OatEnabled();
}
bool IsImageDex2OatEnabled() const {
    return image_dex2oat_enabled_;
}
```

因此最终我们的目的就很明确了，只要把成员变量dex2oat_enabled_的值和image_dex2oat_enabled_的值进行修改，将它们修改成false，就达到了直接禁用的目的。如果要重新开启，则重新还原他们的值为true即可，默认情况下，该值始终是true。 

不过经过验证后发现手淘Atlas是通过禁用IsImageDex2OatEnabled()达到目的的，即它是通过修改image_dex2oat_enabled_而不是dex2oat_enabled_，这一点在兼容性方面十分重要，在一定程度上保障了部分机型的兼容性（比如一加，8.0之后加入了一个变量，导致数据结构向后偏移1字节；VIVO/OPPO部分机型加入变量，导致数据结构向后偏移1字节），因此为了保持策略上的一致性，我们只修改image_dex2oat_enabled_，不修改dex2oat_enabled_。


### 原理与实现

有了以上理论基础，我们必须进行实践，用结论验证猜想，才会有说服力了。

上面已经说到我们只需要修改Runtime中image_dex2oat_enabled_成员变量的值，将其对应的image_dex2oat_enabled_变量修改为false即可。

因此第一步我们需要拿到这个Runtime的地址。

在JNI中，每一个Java中的native方法对应的jni函数，都有一个JNIEnv\* 指针入参，通过该指针变量的GetJavaVM函数，我们可以拿到一个JavaVM\*的指针变量
```
JavaVM *javaVM;
env->GetJavaVM(&javaVM);
```
而JavaVm在JNI中的数据结构定义为（源码地址见 [android-9.0.0_r20/include_jni/jni.h](https://android.googlesource.com/platform/libnativehelper/+/android-9.0.0_r20/include_jni/jni.h)）
```
typedef _JavaVM JavaVM;
struct _JavaVM {
    const struct JNIInvokeInterface* functions;
};
```
可以看到，只有一个JNIInvokeInterface\*指针变量

而在Android中，实际使用的是JavaVMExt（源码地址见 [android-9.0.0_r20/runtime/java_vm_ext.h](https://android.googlesource.com/platform/art/+/android-9.0.0_r20/runtime/java_vm_ext.h)），它继承了JavaVM，它的数据结构可以简单理解为

```
class JavaVMExt : public JavaVM {
private:
    Runtime* const runtime_;
}
```

根据内存布局，我们可以将JavaVMExt等效定义为
```
struct JavaVMExt {
    void *functions;
    void *runtime;
};
```
指针类型，在32位上占4字节，在64位上占8字节。

因此我们只需要将我们之前拿到的JavaVM \*指针，强制转换为JavaVMExt\*指针，通过JavaVMExt\*指针拿到Runtime\*指针
```
JavaVM *javaVM;
env->GetJavaVM(&javaVM);
JavaVMExt *javaVMExt = (JavaVMExt *) javaVM;
void *runtime = javaVMExt->runtime;
```

剩下的事就非常简单了，我们只需要将Runtime数据结构重新定义一遍，这里值得注意的是Android各版本Runtime数据结构不一致，所以需要进行区分，这里以Android 9.0为例。

```
/**
 * 9.0, GcRoot中成员变量是class类型，所以用int代替GcRoot
 */
struct PartialRuntime90 {
    // 64 bit so that we can share the same asm offsets for both 32 and 64 bits.
    uint64_t callee_save_methods_[kCalleeSaveSize90];
    int pre_allocated_OutOfMemoryError_;
    int pre_allocated_NoClassDefFoundError_;
    void *resolution_method_;
    void *imt_conflict_method_;
    // Unresolved method has the same behavior as the conflict method, it is used by the class linker
    // for differentiating between unfilled imt slots vs conflict slots in superclasses.
    void *imt_unimplemented_method_;
 
    // Special sentinel object used to invalid conditions in JNI (cleared weak references) and
    // JDWP (invalid references).
    int sentinel_;
 
    InstructionSet instruction_set_;
    QuickMethodFrameInfo callee_save_method_frame_infos_[kCalleeSaveSize90]; // QuickMethodFrameInfo = uint32_t * 3
 
    void *compiler_callbacks_;
    bool is_zygote_;
    bool must_relocate_;
    bool is_concurrent_gc_enabled_;
    bool is_explicit_gc_disabled_;
    bool dex2oat_enabled_;
    bool image_dex2oat_enabled_;
 
    std::string compiler_executable_;
    std::string patchoat_executable_;
    std::vector<std::string> compiler_options_;
    std::vector<std::string> image_compiler_options_;
    std::string image_location_;
 
    std::string boot_class_path_string_;
    std::string class_path_string_;
    std::vector<std::string> properties_;
};
```

注意，尤其需要注意内部布局中存在对齐问题，即 一、结构体变量中成员的偏移量必须是成员大小的整数倍（0被认为是任何数的整数倍） 二、结构体大小必须是所有成员大小的整数倍。

所以我们必须完整的定义原数据结构，不能存在偏移。否则结构体地址就会错乱。

之后将runtime强制转换为PartialRuntime90\*即可

```
PartialRuntime90 *partialRuntime = (PartialRuntime90 *) runtime;
```
拿到PartialRuntime90之后，直接修改该数据结构中的image_dex2oat_enabled_即可完成禁用

```
partialRuntime->image_dex2oat_enabled_ = false
```
不过这整个流程需要注意几个问题，通过兼容性测试报告反馈来看，存在了如下几个问题
1、Android 5.1-Android 9.0兼容性极好
2、Android 5.0存在部分产商自定义该数据结构，加入了成员导致image_dex2oat_enabled_向后偏移4字节，又或是部分产商Android 5.0使用了Android 5.1的数据结构导致。
3、部分x86的PAD运行arm的APP，此种场景十分特殊，因此我们选择无视此种机型，不处理
4、考虑校验性问题，需要使用一个变量校验我们是否寻址正确，进行适当降级操作，我们选择以指令集变量instruction_set_作为参考。它是一个枚举变量，正常取值范围为int 类型 1-7，如果该值不满足，我们选择不处理，避免不必要的crash问题。
5、一旦寻址失败，我们选择使用兜底策略进行重试，直接查找指令集变量instruction_set_偏移值，转换为另一个公共的数据结构类型进行操作

这里贴出Android 5.0-9.0各系统Runtime的数据结构
```

/**
 * 5.0，GcRoot中成员变量是指针类型，所以用void*代替GcRoot
 */
struct PartialRuntime50 {
    void *callee_save_methods_[kCalleeSaveSize50]; //5.0 5.1 void *
    void *pre_allocated_OutOfMemoryError_;
    void *pre_allocated_NoClassDefFoundError_;
    void *resolution_method_;
    void *imt_conflict_method_;
    void *default_imt_; //5.0 5.1

    InstructionSet instruction_set_;
    QuickMethodFrameInfo callee_save_method_frame_infos_[kCalleeSaveSize50]; // QuickMethodFrameInfo = uint32_t * 3

    void *compiler_callbacks_;
    bool is_zygote_;
    bool must_relocate_;
    bool is_concurrent_gc_enabled_;
    bool is_explicit_gc_disabled_;
    bool dex2oat_enabled_;
    bool image_dex2oat_enabled_;

    std::string compiler_executable_;
    std::string patchoat_executable_;
    std::vector<std::string> compiler_options_;
    std::vector<std::string> image_compiler_options_;
    std::string image_location_;

    std::string boot_class_path_string_;
    std::string class_path_string_;
    std::vector<std::string> properties_;
};

/**
 * 5.1，GcRoot中成员变量是指针类型，所以用void*代替GcRoot
 */
struct PartialRuntime51 {
    void *callee_save_methods_[kCalleeSaveSize50];  //5.0 5.1 void *
    void *pre_allocated_OutOfMemoryError_;
    void *pre_allocated_NoClassDefFoundError_;
    void *resolution_method_;
    void *imt_conflict_method_;
    // Unresolved method has the same behavior as the conflict method, it is used by the class linker
    // for differentiating between unfilled imt slots vs conflict slots in superclasses.
    void *imt_unimplemented_method_;
    void *default_imt_;  //5.0 5.1

    InstructionSet instruction_set_;
    QuickMethodFrameInfo callee_save_method_frame_infos_[kCalleeSaveSize50]; // QuickMethodFrameInfo = uint32_t * 3

    void *compiler_callbacks_;
    bool is_zygote_;
    bool must_relocate_;
    bool is_concurrent_gc_enabled_;
    bool is_explicit_gc_disabled_;
    bool dex2oat_enabled_;
    bool image_dex2oat_enabled_;

    std::string compiler_executable_;
    std::string patchoat_executable_;
    std::vector<std::string> compiler_options_;
    std::vector<std::string> image_compiler_options_;
    std::string image_location_;

    std::string boot_class_path_string_;
    std::string class_path_string_;
    std::vector<std::string> properties_;
};

/**
 * 6.0-7.1，GcRoot中成员变量是class类型，所以用int代替GcRoot
 */
struct PartialRuntime60 {
    // 64 bit so that we can share the same asm offsets for both 32 and 64 bits.
    uint64_t callee_save_methods_[kCalleeSaveSize50];
    int pre_allocated_OutOfMemoryError_;
    int pre_allocated_NoClassDefFoundError_;
    void *resolution_method_;
    void *imt_conflict_method_;
    // Unresolved method has the same behavior as the conflict method, it is used by the class linker
    // for differentiating between unfilled imt slots vs conflict slots in superclasses.
    void *imt_unimplemented_method_;

    // Special sentinel object used to invalid conditions in JNI (cleared weak references) and
    // JDWP (invalid references).
    int sentinel_;

    InstructionSet instruction_set_;
    QuickMethodFrameInfo callee_save_method_frame_infos_[kCalleeSaveSize50]; // QuickMethodFrameInfo = uint32_t * 3

    void *compiler_callbacks_;
    bool is_zygote_;
    bool must_relocate_;
    bool is_concurrent_gc_enabled_;
    bool is_explicit_gc_disabled_;
    bool dex2oat_enabled_;
    bool image_dex2oat_enabled_;

    std::string compiler_executable_;
    std::string patchoat_executable_;
    std::vector<std::string> compiler_options_;
    std::vector<std::string> image_compiler_options_;
    std::string image_location_;

    std::string boot_class_path_string_;
    std::string class_path_string_;
    std::vector<std::string> properties_;
};

/**
 * 8.0-8.1, GcRoot中成员变量是class类型，所以用int代替GcRoot
 */
struct PartialRuntime80 {
    // 64 bit so that we can share the same asm offsets for both 32 and 64 bits.
    uint64_t callee_save_methods_[kCalleeSaveSize80];
    int pre_allocated_OutOfMemoryError_;
    int pre_allocated_NoClassDefFoundError_;
    void *resolution_method_;
    void *imt_conflict_method_;
    // Unresolved method has the same behavior as the conflict method, it is used by the class linker
    // for differentiating between unfilled imt slots vs conflict slots in superclasses.
    void *imt_unimplemented_method_;

    // Special sentinel object used to invalid conditions in JNI (cleared weak references) and
    // JDWP (invalid references).
    int sentinel_;

    InstructionSet instruction_set_;
    QuickMethodFrameInfo callee_save_method_frame_infos_[kCalleeSaveSize80]; // QuickMethodFrameInfo = uint32_t * 3

    void *compiler_callbacks_;
    bool is_zygote_;
    bool must_relocate_;
    bool is_concurrent_gc_enabled_;
    bool is_explicit_gc_disabled_;
    bool dex2oat_enabled_;
    bool image_dex2oat_enabled_;

    std::string compiler_executable_;
    std::string patchoat_executable_;
    std::vector<std::string> compiler_options_;
    std::vector<std::string> image_compiler_options_;
    std::string image_location_;

    std::string boot_class_path_string_;
    std::string class_path_string_;
    std::vector<std::string> properties_;
};

/**
 * 9.0, GcRoot中成员变量是class类型，所以用int代替GcRoot
 */
struct PartialRuntime90 {
    // 64 bit so that we can share the same asm offsets for both 32 and 64 bits.
    uint64_t callee_save_methods_[kCalleeSaveSize90];
    int pre_allocated_OutOfMemoryError_;
    int pre_allocated_NoClassDefFoundError_;
    void *resolution_method_;
    void *imt_conflict_method_;
    // Unresolved method has the same behavior as the conflict method, it is used by the class linker
    // for differentiating between unfilled imt slots vs conflict slots in superclasses.
    void *imt_unimplemented_method_;

    // Special sentinel object used to invalid conditions in JNI (cleared weak references) and
    // JDWP (invalid references).
    int sentinel_;

    InstructionSet instruction_set_;
    QuickMethodFrameInfo callee_save_method_frame_infos_[kCalleeSaveSize90]; // QuickMethodFrameInfo = uint32_t * 3

    void *compiler_callbacks_;
    bool is_zygote_;
    bool must_relocate_;
    bool is_concurrent_gc_enabled_;
    bool is_explicit_gc_disabled_;
    bool dex2oat_enabled_;
    bool image_dex2oat_enabled_;

    std::string compiler_executable_;
    std::string patchoat_executable_;
    std::vector<std::string> compiler_options_;
    std::vector<std::string> image_compiler_options_;
    std::string image_location_;

    std::string boot_class_path_string_;
    std::string class_path_string_;
    std::vector<std::string> properties_;
};
```

数据结构转换完成后，我们需要进行简单的校验，只需要找到一个特征进行校验，这里我们校验指令集变量instruction_set_是否取值正确，该值是一个枚举，正常取值范围1-7

```
/**
 * instruction set
 */
enum class InstructionSet {
    kNone,
    kArm,
    kArm64,
    kThumb2,
    kX86,
    kX86_64,
    kMips,
    kMips64,
    kLast,
};

```

只要该值不在范围内，则认为寻址失败
```
if (partialInstructionSetRuntime->instruction_set_ <= InstructionSet::kNone ||
    partialInstructionSetRuntime->instruction_set_ >= InstructionSet::kLast) {
    return NULL;
}
```

寻址失败后，我们通过运行期指令集特征变量进行重试查找
 
在C++中我们可以通过宏定义，简单获取运行期的指令集
```
#if defined(__arm__)
static constexpr InstructionSet kRuntimeISA = InstructionSet::kArm;
#elif defined(__aarch64__)
static constexpr InstructionSet kRuntimeISA = InstructionSet::kArm64;
#elif defined(__mips__) && !defined(__LP64__)
static constexpr InstructionSet kRuntimeISA = InstructionSet::kMips;
#elif defined(__mips__) && defined(__LP64__)
static constexpr InstructionSet kRuntimeISA = InstructionSet::kMips64;
#elif defined(__i386__)
static constexpr InstructionSet kRuntimeISA = InstructionSet::kX86;
#elif defined(__x86_64__)
static constexpr InstructionSet kRuntimeISA = InstructionSet::kX86_64;
#else
static constexpr InstructionSet kRuntimeISA = InstructionSet::kNone;
#endif
```
需要注意的是如果是InstructionSet::kArm，我们需要优先将其转为成InstructionSet::kThumb2进行查找。如果C++中的运行期指令集变量查找失败，则我们使用Java层获取的指令集变量进行查找


在Java中我们通过反射可以获取运行期指令集
```
private static Integer currentInstructionSet = null;

enum InstructionSet {
    kNone(0),
    kArm(1),
    kArm64(2),
    kThumb2(3),
    kX86(4),
    kX86_64(5),
    kMips(6),
    kMips64(7),
    kLast(8);

    private int instructionSet;

    InstructionSet(int instructionSet) {
        this.instructionSet = instructionSet;
    }

    public int getInstructionSet() {
        return instructionSet;
    }
}

/**
 * 当前指令集字符串，Android 5.0以上支持，以下返回null
 */
private static String getCurrentInstructionSetString() {
    if (Build.VERSION.SDK_INT < 21) {
        return null;
    }
    try {
        Class<?> clazz = Class.forName("dalvik.system.VMRuntime");
        Method currentGet = clazz.getDeclaredMethod("getCurrentInstructionSet");
        return (String) currentGet.invoke(null);
    } catch (Throwable e) {
        e.printStackTrace();
    }
    return null;
}

/**
 * 当前指令集枚举int值，Android 5.0以上支持，以下返回0
 */
private static int getCurrentInstructionSet() {
    if (currentInstructionSet != null) {
        return currentInstructionSet;
    }
    try {
        String invoke = getCurrentInstructionSetString();
        if ("arm".equals(invoke)) {
            currentInstructionSet = InstructionSet.kArm.getInstructionSet();
        } else if ("arm64".equals(invoke)) {
            currentInstructionSet = InstructionSet.kArm64.getInstructionSet();
        } else if ("x86".equals(invoke)) {
            currentInstructionSet = InstructionSet.kX86.getInstructionSet();
        } else if ("x86_64".equals(invoke)) {
            currentInstructionSet = InstructionSet.kX86_64.getInstructionSet();
        } else if ("mips".equals(invoke)) {
            currentInstructionSet = InstructionSet.kMips.getInstructionSet();
        } else if ("mips64".equals(invoke)) {
            currentInstructionSet = InstructionSet.kMips64.getInstructionSet();
        } else if ("none".equals(invoke)) {
            currentInstructionSet = InstructionSet.kNone.getInstructionSet();
        }
    } catch (Throwable e) {
        currentInstructionSet = InstructionSet.kNone.getInstructionSet();
    }
    return currentInstructionSet != null ? currentInstructionSet : InstructionSet.kNone.getInstructionSet();
}   
```


在C++和JAVA层获取到指令集变量的值后，我们通过该变量的值进行寻址
```
template<typename T>
int findOffset(void *start, int regionStart, int regionEnd, T value) {

    if (NULL == start || regionEnd <= 0 || regionStart < 0) {
        return -1;
    }
    char *c_start = (char *) start;

    for (int i = regionStart; i < regionEnd; i += 4) {
        T *current_value = (T *) (c_start + i);
        if (value == *current_value) {
            LOGE("found offset: %d", i);
            return i;
        }
    }
    return -2;
}

//如果是arm则优先使用kThumb2查找，查找不到则再使用arm重试
int isa = (int) kRuntimeISA;
int instructionSetOffset = -1;
instructionSetOffset = findOffset(runtime, 0, 100, isa == (int) InstructionSet::kArm
                                                   ? (int) InstructionSet::kThumb2
                                                   : isa);
if (instructionSetOffset < 0 && isa == (int) InstructionSet::kArm) {
    //如果是arm用thumb2查找失败，则使用arm重试查找
    LOGE("retry find offset when thumb2 fail: %d", InstructionSet::kArm);
    instructionSetOffset = findOffset(runtime, 0, 100, InstructionSet::kArm);
}

//如果kRuntimeISA找不到，则使用java层传入的currentInstructionSet，该值由java层反射获取到传入jni函数中
if (instructionSetOffset <= 0) {
    isa = currentInstructionSet;
    LOGE("retry find offset with currentInstructionSet: %d", isa == (int) InstructionSet::kArm
                                                             ? (int) InstructionSet::kThumb2
                                                             : isa);
    instructionSetOffset = findOffset(runtime, 0, 100, isa == (int) InstructionSet::kArm
                                                       ? (int) InstructionSet::kThumb2 : isa);
    if (instructionSetOffset < 0 && isa == (int) InstructionSet::kArm) {
        LOGE("retry find offset with currentInstructionSet when thumb2 fail: %d",
             InstructionSet::kArm);
        //如果是arm用thumb2查找失败，则使用arm重试查找
        instructionSetOffset = findOffset(runtime, 0, 100, InstructionSet::kArm);
    }
    if (instructionSetOffset <= 0) {
        return NULL;
    }
}
```
查找到instructionSetOffset的地址偏移后，通过各系统的数据结构，计算出image_dex2oat_enabled_地址偏移即可，这里不再详细说明。


### 深坑之Xposed
当你觉得一切很美好的时候，一个深坑突然冒了出来，Xposed！由于Xposed运行期对art进行了hook，实际使用的是libxposed_art.so而不是libart.so，并且对应数据结构存在篡改现象，以5.0-6.0篡改的最为恶劣，其项目地址为 [https://github.com/rovo89/android_art](https://github.com/rovo89/android_art)
 - https://github.com/rovo89/android_art/blob/v89-sdk21/runtime/runtime.h
 - https://github.com/rovo89/android_art/blob/v89-sdk22/runtime/runtime.h
 - https://github.com/rovo89/android_art/blob/v89-sdk23/runtime/runtime.h
 - https://github.com/rovo89/android_art/blob/v89-sdk24/runtime/runtime.h
 - https://github.com/rovo89/android_art/blob/v89-sdk25/runtime/runtime.h

5.0 runtime.h

```
bool is_recompiling_;
bool is_zygote_;
bool is_minimal_framework_;
bool must_relocate_;
bool is_concurrent_gc_enabled_;
bool is_explicit_gc_disabled_;
bool dex2oat_enabled_;
bool image_dex2oat_enabled_;
```

5.1 runtime.h

```
bool is_recompiling_;
bool is_zygote_;
bool is_minimal_framework_;
bool must_relocate_;
bool is_concurrent_gc_enabled_;
bool is_explicit_gc_disabled_;
bool dex2oat_enabled_;
bool image_dex2oat_enabled_;
```

6.0 runtime.h

```
bool is_zygote_;
bool is_minimal_framework_;
bool must_relocate_;
bool is_concurrent_gc_enabled_;
bool is_explicit_gc_disabled_;
bool dex2oat_enabled_;
bool image_dex2oat_enabled_;
```

可以看到，在5.0和5.1上，数据结构多了is_recompiling_和is_minimal_framework_，实际image_dex2oat_enabled_存在向后偏移2字节的问题；在6.0上，数据结构多了is_minimal_framework_，实际image_dex2oat_enabled_存在向后偏移1字节的问题；而在Android 7.0及以上，暂时未存在篡改runtime.h的现象。因此可在native层判断是否存在xposed框架，存在则手动校准偏移值。

判断是否存在xposed函数如下

```
static bool initedXposedInstalled = false;
static bool xposedInstalled = false;
/**
 * xposed是否安装
 * /system/framework/XposedBridge.jar
 * /data/data/de.robv.android.xposed.installer/bin/XposedBridge.jar
 */
bool isXposedInstalled() {
    if (initedXposedInstalled) {
        return xposedInstalled;
    }
    if (!initedXposedInstalled) {
        char *classPath = getenv("CLASSPATH");
        if (classPath == NULL) {
            xposedInstalled = false;
            initedXposedInstalled = true;
            return false;
        }
        char *subString = strstr(classPath, "XposedBridge.jar");
        xposedInstalled = subString != NULL;
        initedXposedInstalled = true;
        return xposedInstalled;
    }
    return xposedInstalled;
}
```

然后进行偏移校准，这里也不再细说。

### 兼容性

做到了如上的几步之后，其实兼容性是相当不错了，通过testin的兼容性测试可以看出，基本已经覆盖常见机型，但是由于testin的兼容性只能覆盖testin上约50%左右的机型，剩余50%机型无法覆盖到，因此我选择了人肉远程真机调试，覆盖剩余50%机型，经过验证后，对testin上99%+的机型都是支持的，且同时支持32位和64位动态库，在兼容性方面，已经远远超越Atlas。

在兼容性测试中，发现一部分机型runtime数据结构存在篡改问题，进一步验证了Atlas为什么修改image_dex2oat_enabled_变量而不是修改dex2oat_enabled_变量，因为dex2oat_enabled_可能存在向后偏移一字节的问题(甚至是2字节，如xposed和一加9.0.2比较新的系统就存在2字节偏移)，导致寻址错误，修改的其实是其原来的地址（即现有真实地址的前一个字节），导致禁用失败。而通过修改image_dex2oat_enabled_变量，即使dex2oat_enabled_向后偏移一字节，由于修改的是image_dex2oat_enabled_，所以实际修改的其实就是dex2oat_enabled_现在偏移后的地址，实际上还是达到了禁用的效果。这里有点绕，可以细细品味一下。这个操作，可以兼容大部分机型。

这里贴出一部分数据结构存在偏移的机型。
![art-address-error1.png](art-address-error1.png)
![art-address-error2.png](art-address-error2.png)
![art-address-error3.png](art-address-error3.png)

### 题外话 Dalvik上dex2opt加速

在art上首次加载插件，会通过禁用dex2oat达到加速效果，那么在dalvik上首次加载插件，其实也存在类似的问题，dalvik上是通过dexopt进行dex的优化操作，这个操作，也是比较耗时的，因此在dalvik上，需要一种类似于dex2oat的方式来达到禁用dex2opt的效果。经过验证后，发现Atlas是通过禁用verify达到一定的加速，因此我们只需要禁用class verify即可。

源码以Android 4.4.4进行分析，见 https://android.googlesource.com/platform/dalvik/+/android-4.4.4_r2/vm/

在Java层我们加载一个Dex是通过DexFile.loadDex()方法进行加载。此方法最终会走到native方法 openDexFileNative，Android 4.4.4的源码如下

https://android.googlesource.com/platform/dalvik/+/android-4.4.4_r2/vm/native/dalvik_system_DexFile.cpp#151

最终会调用到dvmRawDexFileOpen或者dvmJarFileOpen

这两个方法，最终都会先查找缓存文件是否存在，如果不存在，最终都会调用到dvmOptimizeDexFile函数，见：

https://android.googlesource.com/platform/dalvik/+/android-4.4.4_r2/vm/analysis/DexPrepare.cpp#351

而dvmOptimizeDexFile函数开头有这么一段逻辑

```
bool dvmOptimizeDexFile(int fd, off_t dexOffset, long dexLength,
    const char* fileName, u4 modWhen, u4 crc, bool isBootstrap)
{
    const char* lastPart = strrchr(fileName, '/');
    if (lastPart != NULL)
        lastPart++;
    else
        lastPart = fileName;
    ALOGD("DexOpt: --- BEGIN '%s' (bootstrap=%d) ---", lastPart, isBootstrap);
    pid_t pid;
    /*
     * This could happen if something in our bootclasspath, which we thought
     * was all optimized, got rejected.
     */
    //关键代码
    if (gDvm.optimizing) {
        ALOGW("Rejecting recursive optimization attempt on '%s'", fileName);
        return false;
    }
    //此处省略n行代码
}
```

也就是说gDvm.optimizing的值为true的时候，直接被return了，因此我们只需要修改此值为true，即可达到禁用dexopt的目的，但是当设此值为true时，那所有dexopt操作都会发生IOException，导致类加载失败，存在crash风险，所以不能修改此值，看来只能修改class verify为不校验了，没有其他好的方法。事实证明，去掉这一步校验可以节约至少1倍的时间。

此外发现部分4.2.2和4.4.4存在数据结构偏移问题，可通过几个特征数据结构进行重试，重新定位关键数据结构进行重试。这里我们通过 dexOptMode，classVerifyMode，registerMapMode，executionMode四个特征变量的取值范围进行重试定位，有兴趣自行研究一下，不再细说。

通过查看源码发现gDvm是导出的，见 https://android.googlesource.com/platform/dalvik/+/android-4.4.4_r2/vm/Globals.h#740

```
extern struct DvmGlobals gDvm;
```

因此我们只需要借助dlopen和dlsym拿到整个DvmGlobals数据结构的起始地址，修改对应的变量的值即可。不过不幸的是，Android 4.0-4.4这个数据结构各版本都不大一致，需要判断版本进行适配操作。这里以Android 4.4为例。

首先使用dlopen和dlsym获得对应导出符号表地址

```
void *dvm_handle = dlopen("libdvm.so", RTLD_LAZY);
dlerror();//清空错误信息
if (dvm_handle == NULL) {
    return;
}
void *symbol = dlsym(dvm_handle, "gDvm");
const char *error = dlerror();
if (error != NULL) {
    dlclose(dvm_handle);
    return;
}
if (symbol == NULL) {
    LOGE("can't get symbol.");
    dlclose(dvm_handle);
    return;
}
DvmGlobals44 *dvmGlobals = (DvmGlobals44 *) symbol;
```

然后直接修改classVerifyMode的值即可

```
dvmGlobals->classVerifyMode = DexClassVerifyMode::VERIFY_MODE_NONE;
```

至此，就完成了dexopt的禁用class verify操作，可以看到，整个逻辑和art上禁用dex2oat十分相似，只需要找到一个变量，修改它即可。

值得注意的是，这里有很多机型，存在部分数据结构向后偏移的问题，因此，这里得通过几个特征数据结构进行定位，从而得到目标数据结构，这里采用的数据结构为

```
struct DvmGlobalsRetry {
    DexOptimizerMode *dexOptMode;
    DexClassVerifyMode *classVerifyMode;
    RegisterMapMode *registerMapMode;
    ExecutionMode *executionMode;
    /*
     * VM init management.
     */
    bool *initializing;
    bool *optimizing;
};
```

我们通过变量的范围值，优先找到DexOptimizerMode和DexClassVerifyMode的偏移值，然后从DexClassVerifyMode之后找到RegisterMapMode的偏移值，从RegisterMapMode之后找到ExecutionMode的偏移值，最终得到classVerifyMode的偏移值，经过验证，该方法99%+能得到正确的偏移值，从而进行重试。

部分异常机型数据结构偏移如下

![dalvik-address-error1.png](dalvik-address-error1.png)
![dalvik-address-error2.png](dalvik-address-error2.png)

思考：是否AOSP中间某一个版本存在数据结构偏移? 通过查看AOSP源码发现并没有类似偏移，因此不得而知为什么这些Android 4.2.2中dexOptMode向后偏移4字节，Android 4.4.4中dexOptMode向后偏移16字节。偏移值是如此惊人的一致，因此可能的确存在一个git提交，该提交中DvmGlobals数据结构刚好存在如上偏移导致。

Android 4.0-Android 4.4.4，除个别机型偏移值无法计算出来之外，以及dlsym无法获取导出符号表（基本都是X86的PAD），这两种case不予支持，其余testin上4.0-4.4机型全部覆盖，兼容性几乎100%（部分偏移值错误可通过4个特征数据结构进行定位，最终得到正确的偏移值）

### 总结

至此，完成了art上dex2oat禁用达到加速以及dalvik上dex2opt禁用class verify达到加速，前后从技术方案确定到编码，再到兼容性测试，差不多经历了一个月，花费了大量的精力。完成一件事很简单，但是要把一件事做完美，真的不易。且看且珍惜。