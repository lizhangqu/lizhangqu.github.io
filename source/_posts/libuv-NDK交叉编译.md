title: libuv NDK交叉编译
date: 2017-06-04 12:23:54
categories: [NDK]
tags: [NDK, libuv, 交叉编译]
---

移植libuv到android

<!-- more -->

创建工作目录，并进入

```
mkdir android
cd android
```


生成交叉编译工具链

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
```

clone源码

```
git clone git@github.com:libuv/libuv.git
```


导出环境变量(armeabi)

```
export ANDROID_HOME=`pwd`
export TOOLCHAIN=$ANDROID_HOME/toolchain
export PATH=$TOOLCHAIN/bin:$PATH
export TOOL=arm-linux-androideabi
export CC=$TOOLCHAIN/bin/${TOOL}-gcc
export CXX=$TOOLCHAIN/bin/${TOOL}-g++
export LINK=${CXX}
export LD=$TOOLCHAIN/bin/${TOOL}-ld
export AR=$TOOLCHAIN/bin/${TOOL}-ar
export RANLIB=$TOOLCHAIN/bin/${TOOL}-ranlib
export STRIP=$TOOLCHAIN/bin/${TOOL}-strip
export ARCH_FLAGS="-mthumb"
export ARCH_LINK=
export CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64"
export CXXFLAGS="${CFLAGS} -frtti -fexceptions"
export LDFLAGS="${ARCH_LINK}"
export PLATFORM=android
```

编译并安装
```
cd libuv
./autogen.sh
autoreconf -i
./configure --prefix=$TOOLCHAIN/sysroot/usr/local \
       --with-sysroot=$TOOLCHAIN/sysroot \
       --host=arm-linux-androideabi \
       --enable-static \
       --disable-shared
make -j4
make install
```

卸载

```
make uninstall
```


armeabi-v7a

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=arm --install-dir=./toolchain
export TOOL=arm-linux-androideabi
export ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
export ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8"

cd libuv
./autogen.sh
autoreconf -i
./configure --prefix=$TOOLCHAIN/sysroot/usr/local \
       --with-sysroot=$TOOLCHAIN/sysroot \
       --host=arm-linux-androideabi \
       --enable-static \
       --disable-shared
```

x86

```
$ANDROID_NDK/build/tools/make-standalone-toolchain.sh --arch=x86 --install-dir=./toolchain
export TOOL=x86-linux-android
export ARCH_FLAGS="-march=i686 -msse3 -mstackrealign -mfpmath=sse"
export ARCH_LINK=""
./configure --prefix=$TOOLCHAIN/sysroot/usr/local \
       --with-sysroot=$TOOLCHAIN/sysroot \
       --host=x86-linux-androideabi \
       --enable-static \
       --disable-shared
```


demo

将$TOOLCHAIN/sysroot/usr/local中的头文件和libuv.a拷出来备用，复制到项目的thirdparty/libuv目录下


cmake
```
project(UV)
cmake_minimum_required (VERSION 3.6)

include_directories(
  ${PROJECT_SOURCE_DIR}/include/
  ${PROJECT_SOURCE_DIR}/../../../../thirdparty/libuv/include/
  )


add_library(uv STATIC IMPORTED)
set_target_properties(uv
        PROPERTIES IMPORTED_LOCATION ${PROJECT_SOURCE_DIR}/../../../../thirdparty/libuv/lib/libuv.a)


set(UV_FILES
    ${CMAKE_SOURCE_DIR}/uv_native.cpp
)

add_library(
    uv-jni
    SHARED
    ${UV_FILES})

target_link_libraries(
   uv-jni
   uv
   log
)
```


uv_native.h

```

#ifndef UV_NATIVE_H
#define UV_NATIVE_H

#include "jni.h"

#ifndef NELEM
# define NELEM(x) ((int) (sizeof(x) / sizeof((x)[0])))
#endif


#ifndef CLASSNAME
#define CLASSNAME "io/github/lizhangqu/uv/UV"
#endif



#ifdef ANDROID

#include <android/log.h>

#define TAG "UV"

#define ALOGE(fmt, ...) __android_log_print(ANDROID_LOG_ERROR, TAG, fmt, ##__VA_ARGS__)
#define ALOGI(fmt, ...) __android_log_print(ANDROID_LOG_INFO, TAG, fmt, ##__VA_ARGS__)
#define ALOGD(fmt, ...) __android_log_print(ANDROID_LOG_DEBUG, TAG, fmt, ##__VA_ARGS__)
#define ALOGW(fmt, ...) __android_log_print(ANDROID_LOG_WARN, TAG, fmt, ##__VA_ARGS__)
#else
#define ALOGE printf
#define ALOGI printf
#define ALOGD printf
#define ALOGW printf
#endif

#endif //UV_NATIVE_H
```


uv_native.cpp

```

#include "uv_native.h"
#include "uv.h"

void test(JNIEnv *env, jobject thiz) {

  
}

static const JNINativeMethod sMethods[] = {
        {
                const_cast<char *>("test"),
                const_cast<char *>("()V"),
                reinterpret_cast<void *>(test)
        },

};

int registerNativeMethods(JNIEnv *env, const char *className, const JNINativeMethod *methods,
                          const int numMethods) {
    jclass clazz = env->FindClass(className);
    if (!clazz) {
        ALOGE("Native registration unable to find class '%s'\n", className);
        return JNI_FALSE;
    }
    if (env->RegisterNatives(clazz, methods, numMethods) != 0) {
        ALOGE("RegisterNatives failed for '%s'\n", className);
        env->DeleteLocalRef(clazz);
        return JNI_FALSE;
    }
    env->DeleteLocalRef(clazz);
    return JNI_TRUE;
}

jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    JNIEnv *env;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return -1;
    }
    registerNativeMethods(env, CLASSNAME, sMethods, NELEM(sMethods));
    return JNI_VERSION_1_6;
}

```


编写test函数

```
uv_loop_t *loop;

void on_resolved(uv_getaddrinfo_t *resolver, int status, struct addrinfo *res) {
    if (status < 0) {
        ALOGE("getaddrinfo callback error %s\n", uv_err_name(status));
        return;
    }
    char addr[17] = {'\0'};
    uv_ip4_name((struct sockaddr_in *) res->ai_addr, addr, 16);
    ALOGE("ipv4 :%s\n", addr);
    uv_freeaddrinfo(res);
}

void test(JNIEnv *env, jobject thiz) {
    loop = uv_default_loop();
    ALOGE("www.baidu.com is... ");
    uv_getaddrinfo_t resolver;
    int r = uv_getaddrinfo(loop, &resolver, on_resolved, "www.baidu.com", "80", NULL);

    if (r) {
        ALOGE("getaddrinfo call error %s\n", uv_err_name(r));
    } else {
        uv_run(loop, UV_RUN_DEFAULT);
    }
}
```

运行后输出结果

```
06-04 18:51:40.532 27196-27196/io.github.lizhangqu.uv.sample E/UV: www.baidu.com is... 
06-04 18:51:40.536 27196-27196/io.github.lizhangqu.uv.sample E/UV: ipv4 :115.239.211.112
```


demo地址

[libuvSample](https://github.com/lizhangqu/libuvSample)