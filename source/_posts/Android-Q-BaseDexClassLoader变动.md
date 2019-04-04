title: Android Q BaseDexClassLoader变动
date: 2019-04-04 10:46:36
categories: [Android]
tags: [Android, BaseDexClassLoader]
---

上一篇文章讲到一个有意思的地方，见 [谈谈Android P行为变更与内联优化](/2019/04/03/%E8%B0%88%E8%B0%88Android-P%E8%A1%8C%E4%B8%BA%E5%8F%98%E6%9B%B4%E4%B8%8E%E5%86%85%E8%81%94%E4%BC%98%E5%8C%96/) 文章说到，在Andorid Q上加载org.apache.http.legacy.boot.jar和Android P有点不同，Android P上是插入到App的PathClassLoader的pathList中的dexElements完成加载的，而Android Q上加载org.apache.http.legacy.boot.jar的却是一个独立的PathClassLoader对象，但是和App的PathClassLoader属于不同的ClassLoader实例，奇怪的是其父类都是BootClassLoader，根据双亲委托机制，这个类查找显得有点逆天，所以扒了下Android Q的源码，发现是BaseDexClassLoader里做了一点改动。

<!-- more -->

Android Q的BaseDexClassLoader源码可以参考 [BaseDexClassLoader.java](https://android.googlesource.com/platform/libcore/+/refs/tags/android-q-preview-1/dalvik/src/main/java/dalvik/system/BaseDexClassLoader.java)

可以从源码中发现一点猫腻，Android Q中该类多了几个构造函数，并且多了一个十分重要的字段sharedLibraryLoaders，该字段是一个ClassLoader数组

```
/**
 * Array of ClassLoaders that can be used to load classes and resources that the code in
 * {@code pathList} may depend on. This is used to implement Android's
 * <a href=https://developer.android.com/guide/topics/manifest/uses-library-element>
 * shared libraries</a> feature.
 * <p>The shared library loaders are always checked before the {@code pathList} when looking
 * up classes and resources.
 *
 * <p>{@code null} if the class loader has no shared library.
 *
 * @hide
 */
protected final ClassLoader[] sharedLibraryLoaders;

```

在findClass方法中，类查找都会先从sharedLibraryLoaders中进行查找，找不到再从自己的pathList中进行查找，其逻辑如下

```
@Override
protected Class<?> findClass(String name) throws ClassNotFoundException {
// First, check whether the class is present in our shared libraries.
if (sharedLibraryLoaders != null) {
    for (ClassLoader loader : sharedLibraryLoaders) {
        try {
            return loader.loadClass(name);
        } catch (ClassNotFoundException ignored) {
        }
    }
}
// Check whether the class in question is present in the dexPath that
// this classloader operates on.
List<Throwable> suppressedExceptions = new ArrayList<Throwable>();
Class c = pathList.findClass(name, suppressedExceptions);
if (c == null) {
    ClassNotFoundException cnfe = new ClassNotFoundException(
            "Didn't find class \"" + name + "\" on path: " + pathList);
    for (Throwable t : suppressedExceptions) {
        cnfe.addSuppressed(t);
    }
    throw cnfe;
}
return c;
}
```

那么sharedLibraryLoaders是从哪里来呢，其实它是来自其构造函数，该构造函数是hide的，因此我们是无法直接调用到的，因此在Android Q上我们new一个PathClassLoader后，如果使用new出来的实例查找org.apache.http.legacy.boot.jar中的类是无法找到的，这一点和Android P有所区别，Android P由于是将它插入到pathList的dexElements，所以在Android P上是可以找到的。

因为这个特性，在Android P上，使用非标准ClassLoader加载org.apache.http.legacy.boot.jar中的类，可能出现org.apache.http.legacy.boot.jar中的类被不同的ClassLoader加载，如果出现内联，就可能会出现问题。但是在Android Q上，只要我们不使用带sharedLibraryLoaders的构造函数，那么该字段就会是null，查找类就会找不到，只有App的PathClassLoader才能找到org.apache.http.legacy.boot.jar中的类，我们自己使用公共构造函数创建的PathClassLoader都将查找不到，完全可以杜绝内联abort风险。

BaseDexClassLoader的带sharedLibraryLoaders的构造函数和PathClassLoader的带sharedLibraryLoaders构造函数如下

```
/**
 * BaseDexClassLoader implements the Android
 * <a href=https://developer.android.com/guide/topics/manifest/uses-library-element>
 * shared libraries</a> feature by changing the typical parent delegation mechanism
 * of class loaders.
 * <p> Each shared library is associated with its own class loader, which is added to a list of
 * class loaders this BaseDexClassLoader tries to load from in order, immediately checking
 * after the parent.
 * The shared library loaders are always checked before the {@code pathList} when looking
 * up classes and resources.
 *
 * @hide
 */
public BaseDexClassLoader(String dexPath,
        String librarySearchPath, ClassLoader parent, ClassLoader[] sharedLibraryLoaders,
        boolean isTrusted) {
}
```

```
/**
 * @hide
 */
@libcore.api.CorePlatformApi
public PathClassLoader(
        String dexPath, String librarySearchPath, ClassLoader parent,
        ClassLoader[] sharedLibraryLoaders) {
    super(dexPath, librarySearchPath, parent, sharedLibraryLoaders);
}
```

系统创建App的PathClassLoader来自ClassLoaderFactory对象，见 [ClassLoaderFactory.java](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-q-preview-1/core/java/com/android/internal/os/ClassLoaderFactory.java)

```
/**
 * Same as {@code createClassLoader} below, except that no associated namespace
 * is created.
 */
public static ClassLoader createClassLoader(String dexPath,
        String librarySearchPath, ClassLoader parent, String classloaderName,
        List<ClassLoader> sharedLibraries) {
    ClassLoader[] arrayOfSharedLibraries = (sharedLibraries == null)
            ? null
            : sharedLibraries.toArray(new ClassLoader[sharedLibraries.size()]);
    if (isPathClassLoaderName(classloaderName)) {
        return new PathClassLoader(dexPath, librarySearchPath, parent, arrayOfSharedLibraries);
    } else if (isDelegateLastClassLoaderName(classloaderName)) {
        return new DelegateLastClassLoader(dexPath, librarySearchPath, parent,
                arrayOfSharedLibraries);
    }
    throw new AssertionError("Invalid classLoaderName: " + classloaderName);
}
```

而调用ClassLoaderFactory.createClassLoader的方法来自ApplicationLoaders类，源码见 [ApplicationLoaders.java](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-q-preview-1/core/java/android/app/ApplicationLoaders.java)

如果使用了带sharedLibraries的PathClassLoader，那么使用的就是ApplicationLoaders.getDefault().getClassLoaderWithSharedLibraries()方法，其调用来源来自LoadedApk，源码见 [LoadedApk.java](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-q-preview-1/core/java/android/app/LoadedApk.java)，关键代码如下，用了一个递归操作将所有SharedClassLoader串了起来：

```

//创建sharedLibrariesClassLoader
List<ClassLoader> sharedLibraries = createSharedLibrariesLoaders(
        mApplicationInfo.sharedLibraryInfos, isBundledApp, librarySearchPath,
        libraryPermittedPath);

//创建App的ClassLoader
mDefaultClassLoader = ApplicationLoaders.getDefault().getClassLoaderWithSharedLibraries(
        zip, mApplicationInfo.targetSdkVersion, isBundledApp, librarySearchPath,
        libraryPermittedPath, mBaseClassLoader,
        mApplicationInfo.classLoaderName, sharedLibraries);

/**
 * Create a class loader for the {@code sharedLibrary}. Shared libraries are canonicalized,
 * so if we already created a class loader with that shared library, we return it.
 *
 * Implementation notes: the canonicalization of shared libraries is something dex2oat
 * also does.
 */
ClassLoader createSharedLibraryLoader(SharedLibraryInfo sharedLibrary,
        boolean isBundledApp, String librarySearchPath, String libraryPermittedPath) {
    List<String> paths = sharedLibrary.getAllCodePaths();
    List<ClassLoader> sharedLibraries = createSharedLibrariesLoaders(
            sharedLibrary.getDependencies(), isBundledApp, librarySearchPath,
            libraryPermittedPath);
    final String jars = (paths.size() == 1) ? paths.get(0) :
            TextUtils.join(File.pathSeparator, paths);
    // Shared libraries get a null parent: this has the side effect of having canonicalized
    // shared libraries using ApplicationLoaders cache, which is the behavior we want.
    return ApplicationLoaders.getDefault().getClassLoaderWithSharedLibraries(jars,
                mApplicationInfo.targetSdkVersion, isBundledApp, librarySearchPath,
                libraryPermittedPath, /* parent */ null,
                /* classLoaderName */ null, sharedLibraries);
}
private List<ClassLoader> createSharedLibrariesLoaders(List<SharedLibraryInfo> sharedLibraries,
        boolean isBundledApp, String librarySearchPath, String libraryPermittedPath) {
    if (sharedLibraries == null) {
        return null;
    }
    List<ClassLoader> loaders = new ArrayList<>();
    for (SharedLibraryInfo info : sharedLibraries) {
        loaders.add(createSharedLibraryLoader(
                info, isBundledApp, librarySearchPath, libraryPermittedPath));
    }
    return loaders;
}
```

注意此处ClassLoader的parent对象传递的是null，这就解释了为什么用了独立的PathClassLoader，但是其父亲ClassLoader和App的PathClassLoader的父亲都是BootClassLoader的原因。

而List<SharedLibraryInfo> sharedLibraries则来自ApplicationInfo中的sharedLibraryInfos，源码见 [ApplicationInfo.java#828](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-q-preview-1/core/java/android/content/pm/ApplicationInfo.java#828)

```
/**
 * List of all shared libraries this application is linked against.  This
 * field is only set if the {@link PackageManager#GET_SHARED_LIBRARY_FILES
 * PackageManager.GET_SHARED_LIBRARY_FILES} flag was used when retrieving
 * the structure.
 *
 * {@hide}
 */
public List<SharedLibraryInfo> sharedLibraryInfos;
```


该字段也是Android Q中新增的一个字段，其数据结构可以参考[SharedLibraryInfo.java](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-q-preview-1/core/java/android/content/pm/SharedLibraryInfo.java)。

根据以上源码分析就可以完全解释为什么在Android Q上与Android P上org.apache.http.legacy.boot.jar的加载现象不一致的问题，从代码中也可以看出，这个操作可以杜绝Andorid P上org.apache.http.legacy.boot.jar内联abort问题的发生。
