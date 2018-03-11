title: 移除Android P DP1对私有API调用的警告
date: 2018-03-11 09:54:21
categories: [Android]
tags: [Android]
---

Android P Developer Preview 1已经发布了，迫不及待的试了下私有API的调用会出现什么现象

<!-- more -->

经过实验，发现除了控制台会打印出警告日志外，对于dark greylist调用UI上还会显示出对应的警告，而对于light greylist，则只有控制台有日志进行警告，UI上并不会有警告。

控制台的日志大致如下：

```
Accessing hidden method Landroid/content/pm/PackageParser$Package;-><init>(Ljava/lang/String;)V (dark greylist, reflection)
Accessing hidden method Landroid/view/View;->computeFitSystemWindows(Landroid/graphics/Rect;Landroid/graphics/Rect;)Z (light greylist, reflection)
Accessing hidden method Landroid/view/ViewGroup;->makeOptionalFitsSystemWindows()V (light greylist, reflection)
```

而对于debuggable=true的app来说，Activity启动的时候，会在界面上弹出一个Dialog进行警告，警告的内容如下：

![warning.png](warning.png)

而对于release的app来说，Dialog对应换成Toast进行警告，警告内容一样。

通过查看AOSP Developer Preview 1的代码 [android/app/Activity.java#7073](https://android.googlesource.com/platform/frameworks/base/+/android-p-preview-1/core/java/android/app/Activity.java#7073) 发现，在Activity中performStart方法中进行的这个警告，对应的相关代码如下：

```
boolean isAppDebuggable = (mApplication.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
// This property is set for all non-user builds except final release
boolean isApiWarningEnabled = SystemProperties.getInt("ro.art.hiddenapi.warning", 0) == 1;
if (isAppDebuggable || isApiWarningEnabled) {
    if (!mMainThread.mHiddenApiWarningShown && VMRuntime.getRuntime().hasUsedHiddenApi()) {
        // Only show the warning once per process.
        mMainThread.mHiddenApiWarningShown = true;
        String appName = getApplicationInfo().loadLabel(getPackageManager())
                .toString();
        String warning = "Detected problems with API compatibility\n"
                         + "(visit g.co/dev/appcompat for more info)";
        if (isAppDebuggable) {
            new AlertDialog.Builder(this)
                .setTitle(appName)
                .setMessage(warning)
                .setPositiveButton(android.R.string.ok, null)
                .setCancelable(false)
                .show();
        } else {
            Toast.makeText(this, appName + "\n" + warning, Toast.LENGTH_LONG).show();
        }
    }
}
```

那么有没有办法将这个讨人厌的警告干掉呢，经过简单的分析，发现并不是完全不可能，只是方法仅对Developer Preview 1有效，不保证后续的预览版一定有效或者正式Release版一定有效。

我们来看一下这个方法。
  - isAppDebuggable来自构建时设置的debuggable是否为true，改变这个值，只能改变警告的方式，debug用Dialog警告，release用Toast警告，因此这个变量不是关键。
  - isApiWarningEnabled来自SystemProperties中的配置项ro.art.hiddenapi.warning，对于SystemProperties的配置项，如果app的uid不在system group中，则调用set方法会出现错误，因此这个值不能进行改变。
  - VMRuntime.getRuntime().hasUsedHiddenApi()是一个native方法，干预的难度比较大，具体见[dalvik/system/VMRuntime.java#265](https://android.googlesource.com/platform/libcore/+/android-p-preview-1/libart/src/main/java/dalvik/system/VMRuntime.java#265)
  - 所以只有干预mMainThread.mHiddenApiWarningShown这个值，只要在调用performStart前，ActivityThread的mHiddenApiWarningShown变量的值为true，产生这个警告的条件就无法满足


因此问题就变得很简单，只要每次反射调用私有API后让ActivityThread的mHiddenApiWarningShown变为true，这个警告就有可能消失([android/app/ActivityThread.java#269](https://android.googlesource.com/platform/frameworks/base/+/android-p-preview-1/core/java/android/app/ActivityThread.java#269)) 经过简单的测试，发现确实能达到这一效果，如下是测试代码

```
try {
    Class<?> aClass = Class.forName("android.content.pm.PackageParser$Package");
    Constructor<?> declaredConstructor = aClass.getDeclaredConstructor(String.class);
    declaredConstructor.setAccessible(true);
} catch (Exception e) {
    e.printStackTrace();
}


try {
    Class<?> cls = Class.forName("android.app.ActivityThread");
    Method declaredMethod = cls.getDeclaredMethod("currentActivityThread");
    declaredMethod.setAccessible(true);
    Object activityThread = declaredMethod.invoke(null);
    Field mHiddenApiWarningShown = cls.getDeclaredField("mHiddenApiWarningShown");
    mHiddenApiWarningShown.setAccessible(true);
    mHiddenApiWarningShown.setBoolean(activityThread, true);
} catch (Exception e) {
    e.printStackTrace();
}
```

如果在反射调用android.content.pm.PackageParser$Package后，不调用后续的ActivityThread相关部分代码，则进入Activity会产生警告，如果调用了ActivityThread相关部分代码，让mHiddenApiWarningShown为true，则进入Activity不会产生相关警告。

以上代码仅对Android P Developer Preview 1有效，不保证后续版本一定有效，按Google这尿性，谁知道呢~


