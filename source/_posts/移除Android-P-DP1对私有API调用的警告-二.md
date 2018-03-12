title: 移除Android P DP1对私有API调用的警告(二)
date: 2018-03-12 13:49:20
categories: [Android]
tags: [Android]
---

上一篇文章[ 移除Android P DP1对私有API调用的警告](/2018/03/11/移除Android-P-DP1对私有API调用的警告/)简单介绍了如何移除Android P developer preview 1在UI上给出的相关警告，这篇文章主要介绍一下怎么**减少**控制台的日志警告。

<!-- more -->

我们来回顾一下控制台的警告日志是怎么样的，假设我们反射调用如下的代码片段


```
try {
    Class<?> aClass = Class.forName("android.content.pm.PackageParser$Package");
    Constructor<?> declaredConstructor = aClass.getDeclaredConstructor(String.class);
    declaredConstructor.setAccessible(true);
    Object o = declaredConstructor.newInstance(getPackageName());
} catch (Exception e) {
    e.printStackTrace();
}

try {
    AssetManager assetManager = AssetManager.class.newInstance();
    Method addAssetPath = AssetManager.class.getDeclaredMethod("addAssetPath", String.class);
    addAssetPath.setAccessible(true);
    int i = (int) addAssetPath.invoke(assetManager, getApplicationInfo().sourceDir);
} catch (Exception e) {
    e.printStackTrace();
}
```

则对应的控制台会产生如下日志

```
W/zygote: Accessing hidden method Landroid/content/pm/PackageParser$Package;-><init>(Ljava/lang/String;)V (dark greylist, reflection)
W/zygote: Accessing hidden method Landroid/content/res/AssetManager;-><init>()V (light greylist, reflection)
W/zygote: Accessing hidden method Landroid/content/res/AssetManager;->addAssetPath(Ljava/lang/String;)I (light greylist, reflection)
```

我们来捕获一下日志中的关键信息，dark greylist, reflection和light greylist, reflection，也就是说这个警告是我们反射调用私有黑名单或者灰名单中的API引起的，那么我们不用反射调用就可以了。

其实问题很简单，只要使用完整的android.jar进行编译，就可以不用反射，但是这个方法并不能完全解决，因为一些方法是private或者protected的，不用反射根本无法调用到，因此这篇文章介绍的方法，**只能减少控制台日志的警告，不能完全去除控制台日志的警告**。具体的解决思路如下：

   - 仅可以对标记了@hide的public和package访问权限的API有效，对private和protected访问权限的API无效
   - 从[android-hidden-api](https://github.com/anggrayudi/android-hidden-api)上下载完整API的android.jar文件，替换/path/to/AndroidSDK/platforms/android-$level/android.jar文件，替换前注意备份原始文件。
   - 将所有满足条件的API进行修改，从反射调用修改为源码级调用。如果是package访问权限的，在对应包下创建一个辅助类用于调用hide api。

最终上面的示例代码可以修改为

```
package android.content.res;

import android.content.Context;
import android.util.Log;

public class AssetManagerHelper {

    public static AssetManager getAssetManager(Context context) {
        AssetManager assetManager = new AssetManager();
        int i = assetManager.addAssetPath(context.getApplicationInfo().sourceDir);
        Log.e("TAG", "cookie:" + i);
        return assetManager;
    }
}
```

```
package io.github.lizhagqu.demo;

import android.content.Context;
import android.content.pm.PackageParser;
import android.util.Log;

public class PackageHelper {

    public static PackageParser.Package getPackage(Context context) {
        PackageParser.Package aPackage = new PackageParser.Package(context.getPackageName());
        Log.e("TAG", "aPackage:" + aPackage);
        return aPackage;
    }
}

```

调用代码如下：

```
AssetManager assetManager = AssetManagerHelper.getAssetManager(getApplicationContext());
PackageParser.Package aPackage = PackageHelper.getPackage(getApplicationContext());
Log.e("TAG", "AssetManager:" + assetManager);
Log.e("TAG", "package:" + aPackage);
```

再次查看控制台，发现之前的警告日志已经没有了。

**特别注意，这种方式是有局限性的，仅只能干掉访问权限是public或package的，但是被标记了hide的私有API调用的警告！！！**
