title: 获取并还原Flutter Engine Crash堆栈
date: 2019-10-20 08:32:27
categories: [Flutter]
tags: [Flutter, Crash, Backtrace, Stacktrace]
---

对于Flutter来说，大部分crash其实发生在flutter engine中，即libflutter.so中，也就是native crash，对于这部分异常的堆栈，我们要如何进行还原呢。

<!-- more -->

首先我们要借助crash捕获工具捕获native crash，比如可以借助bugly，xcrash([https://github.com/iqiyi/xCrash](https://github.com/iqiyi/xCrash))，甚至是系统的crash dump日志，假设获取到如下堆栈，并将其内容保存到stacktrace.txt文件中

```
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
Build fingerprint: 'OnePlus/OnePlus6/OnePlus6:9/PKQ1.180716.001/1907302100:user/release-keys'
ABI: 'arm'
pid: 1551, tid: 1551, name: b_buyer.example  >>> com.vdian.flutter.wdb_buyer.example <<<
signal 6 (SIGABRT), code -6 (SI_TKILL), fault addr --------
Abort message: '[FATAL:flutter/shell/platform/android/platform_view_android_jni.cc(76)] Check failed: CheckException(env).  '
    r0  00000000  r1  0000060f  r2  00000006  r3  00000008
    r4  0000060f  r5  0000060f  r6  ffd6774c  r7  0000010c
    r8  ffd67834  r9  0000020e  r10 e6123a8c  r11 00000085
    ip  ffd676e8  sp  ffd67738  lr  e7d64fe9  pc  e7d5ce36

backtrace:
    #00 pc 0001ce36  /system/lib/libc.so (abort+58)
    #01 pc 0014053b  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000)
    #02 pc 00137551  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000)
    #03 pc 00136319  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000)
    #04 pc 0016741d  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000)
    #05 pc 00140bcb  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000)
    #06 pc 0014389d  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000)
    #07 pc 0000f239  /system/lib/libutils.so (_ZN7android6Looper9pollInnerEi+632)
    #08 pc 0000ef43  /system/lib/libutils.so (_ZN7android6Looper8pollOnceEiPiS1_PPv+26)
    #09 pc 000b928b  /system/lib/libandroid_runtime.so (_ZN7androidL38android_os_MessageQueue_nativePollOnceEP7_JNIEnvP8_jobjectxi+24)
    #10 pc 003c4215  /system/framework/arm/boot-framework.oat (android.media.MediaExtractor.seekTo [DEDUPED]+92)
    #11 pc 0092f8a5  /system/framework/arm/boot-framework.oat (android.os.MessageQueue.next+204)
    #12 pc 0092d955  /system/framework/arm/boot-framework.oat (android.os.Looper.loop+548)
    #13 pc 007784a3  /system/framework/arm/boot-framework.oat (android.app.ActivityThread.main+674)
    #14 pc 0040dd75  /system/lib/libart.so (art_quick_invoke_stub_internal+68)
    #15 pc 003e735f  /system/lib/libart.so (art_quick_invoke_static_stub+222)
    #16 pc 000a1027  /system/lib/libart.so (_ZN3art9ArtMethod6InvokeEPNS_6ThreadEPjjPNS_6JValueEPKc+154)
    #17 pc 00347e25  /system/lib/libart.so (_ZN3art12_GLOBAL__N_118InvokeWithArgArrayERKNS_33ScopedObjectAccessAlreadyRunnableEPNS_9ArtMethodEPNS0_8ArgArrayEPNS_6JValueEPKc+52)
    #18 pc 00349275  /system/lib/libart.so (_ZN3art12InvokeMethodERKNS_33ScopedObjectAccessAlreadyRunnableEP8_jobjectS4_S4_j+1024)
    #19 pc 002fb36d  /system/lib/libart.so (_ZN3artL13Method_invokeEP7_JNIEnvP8_jobjectS3_P13_jobjectArray+40)
    #20 pc 0011326f  /system/framework/arm/boot-core-oj.oat (java.lang.Class.getDeclaredMethodInternal [DEDUPED]+110)
    #21 pc 00a2b5e3  /system/framework/arm/boot-framework.oat (com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run+114)
    #22 pc 00a314cd  /system/framework/arm/boot-framework.oat (com.android.internal.os.ZygoteInit.main+2836)
    #23 pc 0040dd75  /system/lib/libart.so (art_quick_invoke_stub_internal+68)
    #24 pc 003e735f  /system/lib/libart.so (art_quick_invoke_static_stub+222)
    #25 pc 000a1027  /system/lib/libart.so (_ZN3art9ArtMethod6InvokeEPNS_6ThreadEPjjPNS_6JValueEPKc+154)
    #26 pc 00347e25  /system/lib/libart.so (_ZN3art12_GLOBAL__N_118InvokeWithArgArrayERKNS_33ScopedObjectAccessAlreadyRunnableEPNS_9ArtMethodEPNS0_8ArgArrayEPNS_6JValueEPKc+52)
    #27 pc 00347c4f  /system/lib/libart.so (_ZN3art17InvokeWithVarArgsERKNS_33ScopedObjectAccessAlreadyRunnableEP8_jobjectP10_jmethodIDSt9__va_list+310)
    #28 pc 0028eb11  /system/lib/libart.so (_ZN3art3JNI21CallStaticVoidMethodVEP7_JNIEnvP7_jclassP10_jmethodIDSt9__va_list+444)
    #29 pc 0006dcf3  /system/lib/libandroid_runtime.so (_ZN7_JNIEnv20CallStaticVoidMethodEP7_jclassP10_jmethodIDz+30)
    #30 pc 0006ffd1  /system/lib/libandroid_runtime.so (_ZN7android14AndroidRuntime5startEPKcRKNS_6VectorINS_7String8EEEb+592)
    #31 pc 00001b1b  /system/bin/app_process32 (main+882)
    #32 pc 0008af6d  /system/lib/libc.so (__libc_init+48)
    #33 pc 00001767  /system/bin/app_process32 (_start_main+38)
    #34 pc 00000306  <anonymous:ea2ab000>
```

值得注意的是保存堆栈时，一定要将带第一行带星号的内容保留，因为堆栈还原时会对该行进行识别，再进行还原的。

```
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
```


然后需要获取对于App版本构建时使用的engine的revision，至于这个revision，我建议在打包的时候直接打入代码中，在crash的时候将其附加到额外信息中进行上报，比如放在BuildConfig中，亦或是扔到resources中，怎么处理方便怎么来，比如这里提供两种方式注入。

```
android {
    buildTypes {
        release {
            /**
             * engine revision的值
             */

            //BuildConfig方式注入
            buildConfigField("String", "FLUTTER_REVISION", "\"${revision}\"")
            //资源方式注入
            resValue("string", "FLUTTER_REVISION", "${revision}")
        }
        debug {
            /**
             * engine revision的值
             */

            //BuildConfig方式注入
            buildConfigField "String", "FLUTTER_REVISION", "\"${revision}\""

            //资源方式注入
            resValue("string", "FLUTTER_REVISION", "${revision}")
        }
    }
}
```

flutter engine revision的值位于该文件中

```
/path/to/flutter/bin/internal/engine.version
```

假设此时该文件的内容为

```
b863200c37df4ed378042de11c4e9ff34e4e58c9

```

可以通过如下url浏览该revision下的相关文件

```
https://console.cloud.google.com/storage/browser/flutter_infra/flutter/b863200c37df4ed378042de11c4e9ff34e4e58c9
```

通过如下url直接下载对应的带符号表的libflutter.so文件
```
https://storage.cloud.google.com/flutter_infra/flutter/b863200c37df4ed378042de11c4e9ff34e4e58c9/android-arm-release/symbols.zip
```

这里注意，android-arm是debug构建时对应的文件，android-arm-profile是对应的性能检测构建时的文件，android-arm-release是release构建时对应的文件，对于线上版本，我们应该选择android-arm-release下的文件。如果是arm64的，则应该选择对应cpu abi的文件，如android-arm64-release

下载symblos.zip文件并将保存为symbols.zip文件，然后将其解压

```
cd /path/to/symbols.zip/父目录
mkdir -p ./symbols/armeabi-v7a
unzip symbols.zip -d ./symbols/armeabi-v7a
```

利用ndk-stack将堆栈进行还原

```
/path/to/android-ndk-r16b/ndk-stack -sym /path/to/symbols/armeabi-v7a -dump /path/to/stacktrace.txt
```

得到如下堆栈，可以看到发生crash的代码行数已经很清楚的展现出来了。

```
********** Crash dump: **********
Build fingerprint: 'OnePlus/OnePlus6/OnePlus6:9/PKQ1.180716.001/1907302100:user/release-keys'
pid: 1551, tid: 1551, name: b_buyer.example  >>> com.vdian.flutter.wdb_buyer.example <<<
signal 6 (SIGABRT), code -6 (SI_TKILL), fault addr --------
Stack frame #00 pc 0001ce36  /system/lib/libc.so (abort+58)
Stack frame #01 pc 0014053b  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000): Routine ~LogMessage at /b/s/w/ir/k/src/out/android_release/../../flutter/fml/logging.cc:92
Stack frame #02 pc 00137551  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000): Routine flutter::FlutterViewHandlePlatformMessage(_JNIEnv*, _jobject*, _jstring*, _jobject*, int) at /b/s/w/ir/k/src/out/android_release/../../flutter/shell/platform/android/platform_view_android_jni.cc:76
Stack frame #03 pc 00136319  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000): Routine flutter::PlatformViewAndroid::HandlePlatformMessage(fml::RefPtr<flutter::PlatformMessage>) at /b/s/w/ir/k/src/out/android_release/../../flutter/shell/platform/android/platform_view_android.cc:183
Stack frame #04 pc 0016741d  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000): Routine operator() at /b/s/w/ir/k/src/out/android_release/../../flutter/shell/common/shell.cc:931
Stack frame #05 pc 00140bcb  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000): Routine std::__1::function<void ()>::operator()() const at /b/s/w/ir/k/src/out/android_release/../../third_party/libcxx/include/functional:2419
Stack frame #06 pc 0014389d  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000): Routine fml::MessageLoopAndroid::OnEventFired() at /b/s/w/ir/k/src/out/android_release/../../flutter/fml/platform/android/message_loop_android.cc:92
Stack frame #07 pc 0000f239  /system/lib/libutils.so (_ZN7android6Looper9pollInnerEi+632)
Stack frame #08 pc 0000ef43  /system/lib/libutils.so (_ZN7android6Looper8pollOnceEiPiS1_PPv+26)
Stack frame #09 pc 000b928b  /system/lib/libandroid_runtime.so (_ZN7androidL38android_os_MessageQueue_nativePollOnceEP7_JNIEnvP8_jobjectxi+24)
Stack frame #10 pc 003c4215  /system/framework/arm/boot-framework.oat (android.media.MediaExtractor.seekTo [DEDUPED]+92)
Stack frame #11 pc 0092f8a5  /system/framework/arm/boot-framework.oat (android.os.MessageQueue.next+204)
Stack frame #12 pc 0092d955  /system/framework/arm/boot-framework.oat (android.os.Looper.loop+548)
Stack frame #13 pc 007784a3  /system/framework/arm/boot-framework.oat (android.app.ActivityThread.main+674)
Stack frame #14 pc 0040dd75  /system/lib/libart.so (art_quick_invoke_stub_internal+68)
Stack frame #15 pc 003e735f  /system/lib/libart.so (art_quick_invoke_static_stub+222)
Stack frame #16 pc 000a1027  /system/lib/libart.so (_ZN3art9ArtMethod6InvokeEPNS_6ThreadEPjjPNS_6JValueEPKc+154)
Stack frame #17 pc 00347e25  /system/lib/libart.so (_ZN3art12_GLOBAL__N_118InvokeWithArgArrayERKNS_33ScopedObjectAccessAlreadyRunnableEPNS_9ArtMethodEPNS0_8ArgArrayEPNS_6JValueEPKc+52)
Stack frame #18 pc 00349275  /system/lib/libart.so (_ZN3art12InvokeMethodERKNS_33ScopedObjectAccessAlreadyRunnableEP8_jobjectS4_S4_j+1024)
Stack frame #19 pc 002fb36d  /system/lib/libart.so (_ZN3artL13Method_invokeEP7_JNIEnvP8_jobjectS3_P13_jobjectArray+40)
Stack frame #20 pc 0011326f  /system/framework/arm/boot-core-oj.oat (java.lang.Class.getDeclaredMethodInternal [DEDUPED]+110)
Stack frame #21 pc 00a2b5e3  /system/framework/arm/boot-framework.oat (com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run+114)
Stack frame #22 pc 00a314cd  /system/framework/arm/boot-framework.oat (com.android.internal.os.ZygoteInit.main+2836)
Stack frame #23 pc 0040dd75  /system/lib/libart.so (art_quick_invoke_stub_internal+68)
Stack frame #24 pc 003e735f  /system/lib/libart.so (art_quick_invoke_static_stub+222)
Stack frame #25 pc 000a1027  /system/lib/libart.so (_ZN3art9ArtMethod6InvokeEPNS_6ThreadEPjjPNS_6JValueEPKc+154)
Stack frame #26 pc 00347e25  /system/lib/libart.so (_ZN3art12_GLOBAL__N_118InvokeWithArgArrayERKNS_33ScopedObjectAccessAlreadyRunnableEPNS_9ArtMethodEPNS0_8ArgArrayEPNS_6JValueEPKc+52)
Stack frame #27 pc 00347c4f  /system/lib/libart.so (_ZN3art17InvokeWithVarArgsERKNS_33ScopedObjectAccessAlreadyRunnableEP8_jobjectP10_jmethodIDSt9__va_list+310)
Stack frame #28 pc 0028eb11  /system/lib/libart.so (_ZN3art3JNI21CallStaticVoidMethodVEP7_JNIEnvP7_jclassP10_jmethodIDSt9__va_list+444)
Stack frame #29 pc 0006dcf3  /system/lib/libandroid_runtime.so (_ZN7_JNIEnv20CallStaticVoidMethodEP7_jclassP10_jmethodIDz+30)
Stack frame #30 pc 0006ffd1  /system/lib/libandroid_runtime.so (_ZN7android14AndroidRuntime5startEPKcRKNS_6VectorINS_7String8EEEb+592)
Stack frame #31 pc 00001b1b  /system/bin/app_process32 (main+882)
Stack frame #32 pc 0008af6d  /system/lib/libc.so (__libc_init+48)
Stack frame #33 pc 00001767  /system/bin/app_process32 (_start_main+38)
Stack frame #34 pc 00000306  <anonymous:ea2ab000>
```

如果你只想获取堆栈中某一行调用的代码行数，比如

```
#01 pc 0014053b  /data/app/com.vdian.flutter.wdb_buyer.example-da2lXUv43cG8AaX3DYe5RQ==/lib/arm/libflutter.so (offset 0x11d000)
```

可以使用addr2line命令获取，首先得到pc的值0014053b，然后调用addr2line命令进行获取

```
/path/to/android-ndk-r16b/toolchains/arm-linux-androideabi-4.9/prebuilt/darwin-x86_64/bin/arm-linux-androideabi-addr2line -f -e /path/to/symbols/armeabi-v7a/libflutter.so 0014053b
```

可以得到输出内容

```
~LogMessage
/b/s/w/ir/k/src/out/android_release/../../flutter/fml/logging.cc:92
```

如果你使用的是自己构建的engine引擎代码，那么在构建完成后，请务必保留带符号的libflutter.so文件，否则将无法还原堆栈。

如果你使用bugly进行native crash捕获，则可以借助bugly的符号表上传进行自动还原，见 https://bugly.qq.com/docs/user-guide/symbol-configuration-android/