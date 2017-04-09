title: Android在NDK层使用OpenSSL进行RSA加密
date: 2017-04-09 17:23:44
categories: [NDK]
tags: [NDK, OpenSSL, RSA, Base64]
---


### 前言

**需求：**需要在NDK层对一个Java层的字符串进行RSA加密，然后对加密的结果进行Base64返回到Java层
**方案：**选择使用OpenSSL来实现。

<!-- more -->


### 编译libssl.a和libcrypto.a静态库

在github上找到了一个项目，可以直接将OpenSSL编译成Android可以使用的，项目地址为
 
 - [openssl_for_ios_and_android](https://github.com/leenjewel/openssl_for_ios_and_android)


但是这个项目有点小问题，部分编译脚本需要做点改动，改动后的项目见

 - [openssl_for_ios_and_android](https://github.com/lizhangqu/openssl_for_ios_and_android)


主要做了3个改动:
 
 1. 将最低版本支持从Android 21改到了Android 14
 2. 修复一个armeabi-v7a无法编译出来的问题
 3. 升级了openssl的版本到openssl-1.1.0e

之后将项目clone下来，进入到tools目录，执行build-openssl4android.sh编译脚本

```
./build-openssl4android.sh android-armeabi armeabi-v7a
./build-openssl4android.sh android armeabi
```

这里只编译了armeabi-va7和armeabi架构CPU的so，如果有需要，请自行更改命令参数编译X86等架构的so。

经过很长时间的编译。。。大概要10来分钟吧。。。在根目录下的output会产生一个android目录，里面有openssl-armeabi和openssl-armeabi-v7a两个文件夹，包含了openssl的头文件以及编译好的.a静态库


### 实现JNI函数

编译好后.a静态库，就可以创建jni项目了

#### 进入jni项目根目录，创建Application.mk文件
  
```
APP_ABI := armeabi armeabi-v7a
APP_PLATFORM := android-14
APP_OPTIM := release
APP_STL := c++_static

APP_THIN_ARCHIVE := true
APP_CPPFLAGS := -fpic -fexceptions -frtti
APP_GNUSTL_FORCE_CPP_FEATURES := pic exceptions rtti

```
  
### 进入jni项目根目录，创建Android.mk文件
  
```
LOCAL_PATH := $(call my-dir)

#引用libcrypto.a
include $(CLEAR_VARS)
LOCAL_MODULE := libcrypto
LOCAL_SRC_FILES := $(LOCAL_PATH)/openssl/$(TARGET_ARCH_ABI)/lib/libcrypto.a
include $(PREBUILT_STATIC_LIBRARY)

#引用libssl.a
include $(CLEAR_VARS)
LOCAL_MODULE := libssl
LOCAL_SRC_FILES := $(LOCAL_PATH)/openssl/$(TARGET_ARCH_ABI)/lib/libssl.a
include $(PREBUILT_STATIC_LIBRARY)

include $(CLEAR_VARS)


LOCAL_MODULE    		:= test
LOCAL_SRC_FILES 		:= \
native.cpp \

LOCAL_C_INCLUDES        :=$(LOCAL_PATH)/openssl/openssl-$(TARGET_ARCH_ABI)/include

TARGET_PLATFORM         := android-14

#静态库依赖
LOCAL_STATIC_LIBRARIES  := libssl libcrypto

LOCAL_LDLIBS += -latomic -lz -llog
include $(BUILD_SHARED_LIBRARY)

```

#### 进入jni项目根目录，拷贝编译好的openssl文件

接着将第一步编译好的静态库文件进行拷贝，将output目录下android整个目录进行拷贝，拷贝到jni项目根目录下，拷贝完成后将android目录重命名为openssl


#### 进入jni项目根目录，创建native.cpp，搭建基础的结构

```
#include "jni.h"

template<typename T, int N>
char (&ArraySizeHelper(T (&array)[N]))[N];

#define NELEMS(x) (sizeof(ArraySizeHelper(x)))

#ifndef CLASSNAME
#define CLASSNAME "com/fucknmb/Test"
#endif



jstring native_rsa(JNIEnv *env, jobject thiz, jstring base64PublicKey, jstring content) {
	return NULL;
}


static const JNINativeMethod sMethods[] = {
    {
        const_cast<char *>("native_rsa"),
        const_cast<char *>("(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"),
        reinterpret_cast<void *>(native_rsa)
    }
};

int registerNativeMethods(JNIEnv *env, const char *className, const JNINativeMethod *methods,
                          const int numMethods) {
    jclass clazz = env->FindClass(className);
    if (!clazz) {
        return JNI_FALSE;
    }
    if (env->RegisterNatives(clazz, methods, numMethods) != 0) {
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
    registerNativeMethods(env, CLASSNAME, sMethods, NELEMS(sMethods));
    return JNI_VERSION_1_6;
}

```

#### 声明java层函数

在Java层创建com/fucknmb/Test类，声明一个native函数

```
package com.fucknmb;

import java.util.List;

public class Test {
    public static native final String native_rsa(String base64PublicKey, String content);

    static {
        System.loadLibrary("test");
    }
}

```

#### 实现native_rsa函数

native_rsa函数有两个参数，一个是base64之后的公钥（不含头部和尾部，以及没换行），第二个是待加密的明文内容，该函数的返回值是加密后的密文进行base64。

对于第一个参数，我们需要将其转为公钥文件字符串，追加头部和尾部，其实现如下：

```
/**
 * 根据公钥base64字符串（没换行）生成公钥文本内容
 * @param base64EncodedKey
 * @return
 */
std::string generatePublicKey(std::string base64EncodedKey) {
    std::string publicKey = base64EncodedKey;
    size_t base64Length = 64;//每64个字符一行
    size_t publicKeyLength = base64EncodedKey.size();
    for (size_t i = base64Length; i < publicKeyLength; i += base64Length) {
        //每base64Length个字符，增加一个换行
        if (base64EncodedKey[i] != '\n') {
            publicKey.insert(i, "\n");
        }
        i++;
    }
    //最前面追加公钥begin字符串
    publicKey.insert(0, "-----BEGIN PUBLIC KEY-----\n");
    //最前面追加公钥end字符串
    publicKey.append("\n-----END PUBLIC KEY-----");
    return publicKey;
}
```

openssl rsa加密后，我们需要对密文进行Base64，openssl同样提供了Base64算法，实现如下

```
/**
 * base64 encode
 * @param decoded_bytes
 * @return
 */
std::string base64_encode(const std::string &decoded_bytes) {
    BIO *bio, *b64;
    BUF_MEM *bufferPtr;

    b64 = BIO_new(BIO_f_base64());
    //不换行
    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    bio = BIO_new(BIO_s_mem());
    bio = BIO_push(b64, bio);
    //encode
    BIO_write(bio, decoded_bytes.c_str(), (int) decoded_bytes.length());
    BIO_flush(bio);
    BIO_get_mem_ptr(bio, &bufferPtr);
    //这里的第二个参数很重要，必须赋值
    std::string result(bufferPtr->data, bufferPtr->length);
    BIO_free_all(bio);
    return result;
}

```

**这个函数有一点需要注意的就是这一行**

```
std::string result(bufferPtr->data, bufferPtr->length);
```

**第二个参数表示长度，不能少，否则base64后的字符串长度会出现异常，导致decode的时候末尾会出现一大堆的乱码，而网上大多数的代码，是缺失这一个参数的。**


接下来就是rsa的实现了

```
/**
 * 使用公钥对明文加密
 * @param publicKey
 * @param from
 * @return
 */
std::string encryptRSA(const std::string &publicKey, const std::string &from) {
    BIO *bio = NULL;
    RSA *rsa_public_key = NULL;

    //从字符串读取RSA公钥串
    if ((bio = BIO_new_mem_buf((void *) publicKey.c_str(), -1)) == NULL) {
        std::cout << "BIO_new_mem_buf failed!" << std::endl;
        return NULL;
    }
    //读取公钥
    rsa_public_key = PEM_read_bio_RSA_PUBKEY(bio, NULL, NULL, NULL);

    //异常处理
    if (rsa_public_key == NULL) {
        //资源释放
        BIO_free_all(bio);
        RSA_free(rsa_public_key);
        //清除管理CRYPTO_EX_DATA的全局hash表中的数据，避免内存泄漏
        CRYPTO_cleanup_all_ex_data();
        return NULL;
    }

    //rsa模的位数
    int rsa_size = RSA_size(rsa_public_key);

    //RSA_PKCS1_PADDING 最大加密长度 为 128 -11
    //RSA_NO_PADDING 最大加密长度为  128
    rsa_size = rsa_size - RSA_PKCS1_PADDING_SIZE;

    //动态分配内存，用于存储加密后的密文
    unsigned char *to = (unsigned char *) malloc(rsa_size + 1);
    //填充0
    memset(to, 0, rsa_size + 1);

    //明文长度
    int flen = from.length();

    //加密，返回值为加密后的密文长度，-1表示失败
    int status = RSA_public_encrypt(flen, (const unsigned char *) from.c_str(), to, rsa_public_key,
                                    RSA_PKCS1_PADDING);
    //异常处理
    if (status < 0) {
        //资源释放
        free(to);
        BIO_free_all(bio);
        RSA_free(rsa_public_key);
        //清除管理CRYPTO_EX_DATA的全局hash表中的数据，避免内存泄漏
        CRYPTO_cleanup_all_ex_data();
        return NULL;
    }

    //赋值密文
    static std::string result((char *) to, status);

    //资源释放
    free(to);
    BIO_free_all(bio);
    RSA_free(rsa_public_key);
    //清除管理CRYPTO_EX_DATA的全局hash表中的数据，避免内存泄漏
    CRYPTO_cleanup_all_ex_data();
    return result;
}
```

**同样这个函数也有几个地方需要注意：**

**第一点：**

```
static std::string result((char *) to, status);
```

**第二个参数表示密文长度，一般来说，这个值会是128，如果第二个值不传，会导致加密后的密文经过string的构造函数后，丢失一部分数据，导致数据的不正确**

**第二点:**

```
rsa_size = rsa_size - RSA_PKCS1_PADDING_SIZE;
```

**对于RSA_PKCS1_PADDING_SIZE，最大加密长度为需要减去11**

**第三点:**

```
//明文长度
int flen = from.length();

//加密，返回值为加密后的密文长度，-1表示失败
int status = RSA_public_encrypt(flen, (const unsigned char *) from.c_str(), to, rsa_public_key,
                                RSA_PKCS1_PADDING);

```

**RSA_public_encrypt函数的第一个参数传的是明文长度，而不是最大加密长度rsa_size，网上的所有代码这个参数都是传错的，传了rsa_size，而实际上这个参数的参数名是flen，表示from字符串的length。如果这个参数传了最大加密长度，将直接导致java层无法正确解密JNI层加密后的数据。**


最后不要忘记加头文件的引用

```
#include <openssl/bio.h>
#include <openssl/buffer.h>
#include <openssl/evp.h>
#include <openssl/rsa.h>
#include <openssl/pem.h>
#include <iostream>
using std::string;
```


需要的函数都有了，实现以下native_rsa函数，简单组装一下以上函数即可

```
jstring native_rsa(JNIEnv *env, jobject thiz, jstring base64PublicKey, jstring content) {
    //jstring 转 char*
    char *base64PublicKeyChars = (char *) env->GetStringUTFChars(base64PublicKey, NULL);
    //char* 转 string
    string base64PublicKeyString = string(base64PublicKeyChars);
    //生成公钥字符串
    string generatedPublicKey = generatePublicKey(base64PublicKeyString);
    //释放
    env->ReleaseStringUTFChars(base64PublicKey, base64PublicKeyChars);
    //jstring 转 char*
    char *contentChars = (char *) env->GetStringUTFChars(content, NULL);
    //char* 转 string
    string contentString = string(contentChars);
    //释放
    env->ReleaseStringUTFChars(content, contentChars);

    //调用RSA加密函数加密
    string rsaResult = encryptRSA(generatedPublicKey, contentString);
    if (rsaResult.empty()) {
        return NULL;
    }
    //将密文进行base64
    string base64RSA = base64_encode(rsaResult);
    if (base64RSA.empty()) {
        return NULL;
    }
    //string -> char* -> jstring 返回
    jstring result = env->NewStringUTF(base64RSA.c_str());
    return result;
}
```

#### 私钥解密

如果你还需要用的私钥解密部分，可以继续实现base64的decode函数，以及rsa的私钥串生成函数，rsa的解密函数

base64 decode函数的实现如下：

```
/**
 * base64 decode
 * @param encoded_bytes
 * @return
 */
std::string base64_decode(const std::string &encoded_bytes) {
    BIO *bioMem, *b64;

    bioMem = BIO_new_mem_buf((void *) encoded_bytes.c_str(), -1);
    b64 = BIO_new(BIO_f_base64());
    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    bioMem = BIO_push(b64, bioMem);

    //获得解码长度
    size_t buffer_length = BIO_get_mem_data(bioMem, NULL);

    char *decode = (char *) malloc(buffer_length + 1);
    //填充0
    memset(decode, 0, buffer_length + 1);

    BIO_read(bioMem, (void *) decode, (int) buffer_length);

    static std::string decoded_bytes(decode);

    BIO_free_all(bioMem);

    return decoded_bytes;
}
```


rsa的私钥串生成函数的试下如下：

```
/**
 * 根据私钥base64字符串（没换行）生成私钥文本内容
 * @param base64EncodedKey
 * @return
 */
std::string generatePrivateKey(std::string base64EncodedKey) {
    std::string privateKey = base64EncodedKey;
    size_t base64Length = 64;//每64个字符一行
    size_t privateKeyLength = base64EncodedKey.size();
    for (size_t i = base64Length; i < privateKeyLength; i += base64Length) {
        //每base64Length个字符，增加一个换行
        if (base64EncodedKey[i] != '\n') {
            privateKey.insert(i, "\n");
        }
        i++;
    }
    //最前面追加私钥begin字符串
    privateKey.insert(0, "-----BEGIN PRIVATE KEY-----\n");
    //最后面追加私钥end字符串
    privateKey.append("\n-----END PRIVATE KEY-----");
    return privateKey;
}
```

私钥解密函数的实现如下：

```
/**
 * 使用私钥对密文解密
 * @param privetaKey
 * @param from
 * @return
 */
std::string decryptRSA(const std::string &privetaKey, const std::string &from) {
    BIO *bio = NULL;
    RSA *rsa_private_key = NULL;
    //从字符串读取RSA公钥串
    if ((bio = BIO_new_mem_buf((void *) privetaKey.c_str(), -1)) == NULL) {
        std::cout << "BIO_new_mem_buf failed!" << std::endl;
        return NULL;
    }
    //读取私钥
    rsa_private_key = PEM_read_bio_RSAPrivateKey(bio, NULL, NULL, NULL);

    //异常处理
    if (rsa_private_key == NULL) {
        //资源释放
        BIO_free_all(bio);
        RSA_free(rsa_private_key);
        //清除管理CRYPTO_EX_DATA的全局hash表中的数据，避免内存泄漏
        CRYPTO_cleanup_all_ex_data();
        return NULL;
    }

    //rsa模的位数
    int rsa_size = RSA_size(rsa_private_key);

    //动态分配内存，用于存储解密后的明文
    unsigned char *to = (unsigned char *) malloc(rsa_size + 1);
    //填充0
    memset(to, 0, rsa_size + 1);

    //密文长度
    int flen = from.length();

    // RSA_NO_PADDING
    // RSA_PKCS1_PADDING
    //解密，返回值为解密后的名文长度，-1表示失败
    int status = RSA_private_decrypt(flen, (const unsigned char *) from.c_str(), to, rsa_private_key,
                                     RSA_PKCS1_PADDING);
    //异常处理率
    if (status < 0) {
        //释放资源
        free(to);
        BIO_free_all(bio);
        RSA_free(rsa_private_key);
        //清除管理CRYPTO_EX_DATA的全局hash表中的数据，避免内存泄漏
        CRYPTO_cleanup_all_ex_data();
        return NULL;
    }

    //赋值明文，是否需要指定to的长度？
    static std::string result((char *) to);

    //释放资源
    free(to);
    BIO_free_all(bio);
    RSA_free(rsa_private_key);
    //清除管理CRYPTO_EX_DATA的全局hash表中的数据，避免内存泄漏
    CRYPTO_cleanup_all_ex_data();
    return result;
}
```

如果你要解密公钥加密后的密文，只需要这样调用即可返回明文

```
//公钥串和私钥串
string generatedPublicKey = generatePublicKey(base64PublicKey);
string generatedPrivetKey = generatePrivateKey(base64PrivateKey);
    
string content("just a test");
//加密
string result = encryptRSA(generatedPublicKey, content);
//encode
string base64RSA = base64_encode(result);

//decode
string decodeBase64RSA = base64_decode(base64RSA);
//解密
string origin = decryptRSA(generatedPrivetKey, decodeBase64RSA);
```

最后注意一下base64PublicKey和base64PrivateKey，这两个字符串是不包含换行的，就是私钥和公钥的encoded之后的字节数组base64后的值，因此需要自己调用generatePublicKey和generatePrivateKey追加头和尾。

#### RSA公钥和私钥的生成


生成私钥

```
openssl genrsa -out rsa_private_key.pem 1024
```

这条命令让openssl随机生成了一份私钥，加密长度是1024位。加密长度是指理论上最大允许”被加密的信息“长度的限制，也就是明文的长度限制。随着这个参数的增大（比方说2048），允许的明文长度也会增加，但同时也会造成计算复杂度的极速增长。一般推荐的长度就是1024位（128字节，之前的代码的最大加密长度128就是这么来的）。

生成公钥

```
openssl rsa -in rsa_private_key.pem -out rsa_public_key.pem -pubout 
```

密钥文件最终将数据通过Base64编码进行存储。可以看到上述生成的密钥文件内容每一行的长度都很规律。这是由于RFC2045中规定：The encoded output stream must be represented in lines of no more than 76 characters each。也就是说Base64编码的数据每行最多不超过76字符，对于超长数据需要按行分割。

上面的generatePublicKey和generatePrivateKey函数我们是按64位一行进行分割的，如果你有需要，可以将值修改为76。


第一步生成私钥文件不能直接使用，需要进行PKCS#8编码：

```
openssl pkcs8 -topk8 -in rsa_private_key.pem -out pkcs8_rsa_private_key.pem -nocrypt
```


第二步和第三步生成的公钥和私钥就可以用了，这里有个问题需要注意，如果你的公钥和私钥是类似下面这种格式的

```
-----BEGIN PUBLIC KEY-----
....
-----END PUBLIC KEY-----


-----BEGIN PRIVATE KEY-----
....
-----END PRIVATE KEY-----
```

那么，你无需调用generatePublicKey或者generatePrivateKey函数，此时已经是需要的公钥串和私钥串，但是如果你的公钥和私钥没有头部和尾部，并且不是换行的，就需要调用一下进行转换，因为我这边Java层传入的是后者，所以需要调用generatePublicKey或者generatePrivateKey进行转换。


#### Java层调用公钥加密函数部分


```
String base64PublicKey = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDP0tzYxBF5IGfNvuIHzAqvza/ZxfH8aEiPFA4nY/W3js+cG3JUU86Jkc7jUG9XfGdW6SJ38ANs5tyWqYkJyoUErB2PjQQQDmHhbgpBUSeOdwGr/LPtrTrotrNXwpRY9eodkcbcMlbT0gvdnohRSISCjJ2KmFcBMkeO9R2DWe6oIwIDAQAB";
String result = com.fucknmb.Test.native_rsa(base64PublicKey,"I am test");
```