title: 一种纯Java层绕过Android P私有函数调用限制的方式
date: 2018-10-05 11:47:38
categories: [Android]
tags: [Android, UnSafe]
---

核心思想就是使用UnSafe直接操作内存

<!-- more -->

先来看一段代码：

```
template<typename T>
inline Action GetMemberAction(T* member,
                              Thread* self,
                              std::function<bool(Thread*)> fn_caller_is_trusted,
                              AccessMethod access_method)
    REQUIRES_SHARED(Locks::mutator_lock_) {
  DCHECK(member != nullptr);
  // Decode hidden API access flags.
  // NB Multiple threads might try to access (and overwrite) these simultaneously,
  // causing a race. We only do that if access has not been denied, so the race
  // cannot change Java semantics. We should, however, decode the access flags
  // once and use it throughout this function, otherwise we may get inconsistent
  // results, e.g. print whitelist warnings (b/78327881).
  HiddenApiAccessFlags::ApiList api_list = member->GetHiddenApiAccessFlags();
  Action action = GetActionFromAccessFlags(member->GetHiddenApiAccessFlags());
  if (action == kAllow) {
    // Nothing to do.
    return action;
  }
  // Member is hidden. Invoke `fn_caller_in_platform` and find the origin of the access.
  // This can be *very* expensive. Save it for last.
  if (fn_caller_is_trusted(self)) {
    // Caller is trusted. Exit.
    return kAllow;
  }
  // Member is hidden and caller is not in the platform.
  return detail::GetMemberActionImpl(member, api_list, action, access_method);
}
```


从上述代码可以看到，当调用者来自系统classloader加载时，即fn_caller_is_trusted(self)返回了true即可绕过限制，因此问题变成了如何将对应类的class对象中的classloader设为null，即BootClassLoader加载。

反射直接拿classloader是行不通的，因为该字段在深灰名单中，会抛NoSuchFiledException。

因此问题就变得复杂。


这里介绍一个Java中的上帝类sun.misc.Unsafe，该类很强大，可以直接操作对象内存，这也是为什么取名为Unsafe的原因，相关使用可以看 http://mishadoff.com/blog/java-magic-part-4-sun-dot-misc-dot-unsafe/ 你可能之前从来没有使用过这个类，但是其实你已经不知不觉中使用到了，Gson中就使用了该类进行对象创建工作。

这个类有一个静态方法getUnsafe，但是该方法做了调用限制，只允许系统Classloader加载的类进行调用，否则会抛异常。但是它有一个静态变量theUnsafe，该字段在Android P中是浅灰名单，可以安全调用。并且这个类在android.jar中是引用不到的，因此必须做一层封装才可进行调用


```
package github.io.lizhangqu.unsafe;

import android.annotation.TargetApi;

import sun.misc.Unsafe;

import java.lang.reflect.Field;

@SuppressWarnings({"unchecked", "unused", "WeakerAccess"})
public class UnSafeWrapper {

    private static final UnSafeWrapper THE_ONE = new UnSafeWrapper();
    private static final UnSafeWrapper theUnsafe = THE_ONE;

    private static final Unsafe unsafe;

    static {
        try {
            final Field field = Unsafe.class.getDeclaredField("theUnsafe");
            field.setAccessible(true);
            unsafe = (Unsafe) field.get(null);
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
    }

    public static UnSafeWrapper getUnSafe() {
        return THE_ONE;
    }

    /**
     * Allocates an instance of the given class without running the constructor.
     * The class' will be run, if necessary.
     */
    public <T> T allocateInstance(Class<T> clazz) throws InstantiationException {
        return (T) unsafe.allocateInstance(clazz);
    }

    /**
     * Gets the offset from the start of an array object's memory to
     * the memory used to store its initial (zeroeth) element.
     *
     * @param clazz non-null; class in question; must be an array class
     * @return the offset to the initial element
     */
    public int arrayBaseOffset(Class<?> clazz) {
        return unsafe.arrayBaseOffset(clazz);
    }

    /**
     * Gets the size of each element of the given array class.
     *
     * @param clazz non-null; class in question; must be an array class
     * @return &gt; 0; the size of each element of the array
     */
    public int arrayIndexScale(Class<?> clazz) {
        return unsafe.arrayIndexScale(clazz);
    }

    /**
     * Performs a compare-and-set operation on an <code>int</code>
     * field within the given object.
     *
     * @param obj           non-null; object containing the field
     * @param offset        offset to the field within <code>obj</code>
     * @param expectedValue expected value of the field
     * @param newValue      new value to store in the field if the contents are
     *                      as expected
     * @return <code>true</code> if the new value was in fact stored, and
     * <code>false</code> if not
     */
    public boolean compareAndSwapInt(Object obj, long offset, int expectedValue, int newValue) {
        return unsafe.compareAndSwapInt(obj, offset, expectedValue, newValue);
    }

    /**
     * Performs a compare-and-set operation on a <code>long</code>
     * field within the given object.
     *
     * @param obj           non-null; object containing the field
     * @param offset        offset to the field within <code>obj</code>
     * @param expectedValue expected value of the field
     * @param newValue      new value to store in the field if the contents are
     *                      as expected
     * @return <code>true</code> if the new value was in fact stored, and
     * <code>false</code> if not
     */
    public boolean compareAndSwapLong(Object obj, long offset, long expectedValue, long newValue) {
        return unsafe.compareAndSwapLong(obj, offset, expectedValue, newValue);
    }

    /**
     * Performs a compare-and-set operation on an <code>Object</code>
     * field (that is, a reference field) within the given object.
     *
     * @param obj           non-null; object containing the field
     * @param offset        offset to the field within <code>obj</code>
     * @param expectedValue expected value of the field
     * @param newValue      new value to store in the field if the contents are
     *                      as expected
     * @return <code>true</code> if the new value was in fact stored, and
     * <code>false</code> if not
     */
    public boolean compareAndSwapObject(Object obj, long offset, Object expectedValue, Object newValue) {
        return unsafe.compareAndSwapObject(obj, offset, expectedValue, newValue);
    }

    /**
     * Gets an <code>int</code> field from the given object.
     *
     * @param obj    non-null; object containing the field
     * @param offset offset to the field within <code>obj</code>
     * @return the retrieved value
     */
    public int getInt(Object obj, long offset) {
        return unsafe.getInt(obj, offset);
    }

    /**
     * Gets an <code>int</code> field from the given object,
     * using <code>volatile</code> semantics.
     *
     * @param obj    non-null; object containing the field
     * @param offset offset to the field within <code>obj</code>
     * @return the retrieved value
     */
    public int getIntVolatile(Object obj, long offset) {
        return unsafe.getIntVolatile(obj, offset);
    }

    /**
     * Gets a <code>long</code> field from the given object,
     * using <code>volatile</code> semantics.
     *
     * @param obj    non-null; object containing the field
     * @param offset offset to the field within <code>obj</code>
     * @return the retrieved value
     */
    public long getLong(Object obj, long offset) {
        return unsafe.getLong(obj, offset);
    }

    /**
     * Gets a <code>long</code> field from the given object,
     * using <code>volatile</code> semantics.
     *
     * @param obj    non-null; object containing the field
     * @param offset offset to the field within <code>obj</code>
     * @return the retrieved value
     */
    public long getLongVolatile(Object obj, long offset) {
        return unsafe.getLongVolatile(obj, offset);
    }

    /**
     * Gets an <code>Object</code> field from the given object.
     *
     * @param obj    non-null; object containing the field
     * @param offset offset to the field within <code>obj</code>
     * @return the retrieved value
     */
    public Object getObject(Object obj, long offset) {
        return unsafe.getObject(obj, offset);
    }

    /**
     * Gets an <code>Object</code> field from the given object,
     * using <code>volatile</code> semantics.
     *
     * @param obj    non-null; object containing the field
     * @param offset offset to the field within <code>obj</code>
     * @return the retrieved value
     */
    public Object getObjectVolatile(Object obj, long offset) {
        return unsafe.getObjectVolatile(obj, offset);
    }

    /**
     * Gets the raw byte offset from the start of an object's memory to
     * the memory used to store the indicated instance field.
     *
     * @param field non-null; the field in question, which must be an
     *              instance field
     * @return the offset to the field
     */
    public long objectFieldOffset(Field field) {
        return unsafe.objectFieldOffset(field);
    }

    /**
     * Parks the calling thread for the specified amount of time,
     * unless the "permit" for the thread is already available (due to
     * a previous call to {@link #unpark}. This method may also return
     * spuriously (that is, without the thread being told to unpark
     * and without the indicated amount of time elapsing).
     * <p>
     * <p>See {@link java.util.concurrent.locks.LockSupport} for more
     * in-depth information of the behavior of this method.</p>
     *
     * @param absolute whether the given time value is absolute
     *                 milliseconds-since-the-epoch (<code>true</code>) or relative
     *                 nanoseconds-from-now (<code>false</code>)
     * @param time     the (absolute millis or relative nanos) time value
     */
    public void park(boolean absolute, long time) {
        unsafe.park(absolute, time);
    }

    /**
     * Unparks the given object, which must be a {@link Thread}.
     * <p>
     * <p>See {@link java.util.concurrent.locks.LockSupport} for more
     * in-depth information of the behavior of this method.</p>
     *
     * @param obj non-null; the object to unpark
     */
    public void unpark(Object obj) {
        unsafe.unpark(obj);
    }

    /**
     * Stores an <code>int</code> field into the given object.
     *
     * @param obj      non-null; object containing the field
     * @param offset   offset to the field within <code>obj</code>
     * @param newValue the value to store
     */
    public void putInt(Object obj, long offset, int newValue) {
        unsafe.putInt(obj, offset, newValue);
    }

    /**
     * Stores an <code>int</code> field into the given object,
     * using <code>volatile</code> semantics.
     *
     * @param obj      non-null; object containing the field
     * @param offset   offset to the field within <code>obj</code>
     * @param newValue the value to store
     */
    public void putIntVolatile(Object obj, long offset, int newValue) {
        unsafe.putIntVolatile(obj, offset, newValue);
    }

    /**
     * Stores a <code>long</code> field into the given object.
     *
     * @param obj      non-null; object containing the field
     * @param offset   offset to the field within <code>obj</code>
     * @param newValue the value to store
     */
    public void putLong(Object obj, long offset, long newValue) {
        unsafe.putLong(obj, offset, newValue);
    }

    /**
     * Stores a <code>long</code> field into the given object,
     * using <code>volatile</code> semantics.
     *
     * @param obj      non-null; object containing the field
     * @param offset   offset to the field within <code>obj</code>
     * @param newValue the value to store
     */
    public void putLongVolatile(Object obj, long offset, long newValue) {
        unsafe.putLongVolatile(obj, offset, newValue);
    }

    /**
     * Stores an <code>Object</code> field into the given object.
     *
     * @param obj      non-null; object containing the field
     * @param offset   offset to the field within <code>obj</code>
     * @param newValue the value to store
     */
    public void putObject(Object obj, long offset, Object newValue) {
        unsafe.putObject(obj, offset, newValue);
    }

    /**
     * Stores an <code>Object</code> field into the given object,
     * using <code>volatile</code> semantics.
     *
     * @param obj      non-null; object containing the field
     * @param offset   offset to the field within <code>obj</code>
     * @param newValue the value to store
     */
    public void putObjectVolatile(Object obj, long offset, Object newValue) {
        unsafe.putObjectVolatile(obj, offset, newValue);
    }

    /**
     * Lazy set an int field.
     */
    public void putOrderedInt(Object obj, long offset, int newValue) {
        unsafe.putOrderedInt(obj, offset, newValue);
    }

    /**
     * Lazy set a long field.
     */
    public void putOrderedLong(Object obj, long offset, long newValue) {
        unsafe.putOrderedLong(obj, offset, newValue);
    }

    /**
     * Lazy set an object field.
     */
    public void putOrderedObject(Object obj, long offset, Object newValue) {
        unsafe.putOrderedObject(obj, offset, newValue);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public int addressSize() {
        return unsafe.addressSize();
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public int pageSize() {
        return unsafe.pageSize();
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public long allocateMemory(long bytes) {
        return unsafe.allocateMemory(bytes);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public void freeMemory(long address) {
        unsafe.freeMemory(address);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public void setMemory(long address, long bytes, byte value) {
        unsafe.setMemory(address, bytes, value);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public byte getByte(long address) {
        return unsafe.getByte(address);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public void putByte(Object obj, long offset, byte newValue) {
        unsafe.putByte(obj, offset, newValue);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public short getShort(long address) {
        return unsafe.getShort(address);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public void putShort(Object obj, long offset, short newValue) {
        unsafe.putShort(obj, offset, newValue);
    }

    /**
     * @since 1.8
     */
    public char getChar(long address) {
        return unsafe.getChar(address);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public void putChar(Object obj, long offset, char newValue) {
        unsafe.putChar(obj, offset, newValue);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public int getInt(long address) {
        return unsafe.getInt(address);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public long getLong(long address) {
        return unsafe.getLong(address);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public float getFloat(long address) {
        return unsafe.getFloat(address);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public void putFloat(Object obj, long offset, float newValue) {
        unsafe.putFloat(obj, offset, newValue);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public double getDouble(long address) {
        return unsafe.getDouble(address);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public void putDouble(Object obj, long offset, double newValue) {
        unsafe.putDouble(obj, offset, newValue);
    }

    /**
     * @since 1.8
     */
    @TargetApi(24)
    public void copyMemory(long srcAddr, long dstAddr, long bytes) {
        unsafe.copyMemory(srcAddr, dstAddr, bytes);
    }

    // The following contain CAS-based Java implementations used on
    // platforms not supporting native instructions

    /**
     * Atomically adds the given value to the current value of a field
     * or array element within the given object {@code o}
     * at the given {@code offset}.
     *
     * @param o      object/array to update the field/element in
     * @param offset field/element offset
     * @param delta  the value to add
     * @return the previous value
     * @since 1.8
     */
    // @HotSpotIntrinsicCandidate
    @TargetApi(24)
    public int getAndAddInt(Object o, long offset, int delta) {
        return unsafe.getAndAddInt(o, offset, delta);
    }

    /**
     * Atomically adds the given value to the current value of a field
     * or array element within the given object {@code o}
     * at the given {@code offset}.
     *
     * @param o      object/array to update the field/element in
     * @param offset field/element offset
     * @param delta  the value to add
     * @return the previous value
     * @since 1.8
     */
    // @HotSpotIntrinsicCandidate
    @TargetApi(24)
    public long getAndAddLong(Object o, long offset, long delta) {
        return unsafe.getAndAddLong(o, offset, delta);
    }

    /**
     * Atomically exchanges the given value with the current value of
     * a field or array element within the given object {@code o}
     * at the given {@code offset}.
     *
     * @param o        object/array to update the field/element in
     * @param offset   field/element offset
     * @param newValue new value
     * @return the previous value
     * @since 1.8
     */
    // @HotSpotIntrinsicCandidate
    @TargetApi(24)
    public int getAndSetInt(Object o, long offset, int newValue) {
        return unsafe.getAndSetInt(o, offset, newValue);
    }

    /**
     * Atomically exchanges the given value with the current value of
     * a field or array element within the given object {@code o}
     * at the given {@code offset}.
     *
     * @param o        object/array to update the field/element in
     * @param offset   field/element offset
     * @param newValue new value
     * @return the previous value
     * @since 1.8
     */
    // @HotSpotIntrinsicCandidate
    @TargetApi(24)
    public long getAndSetLong(Object o, long offset, long newValue) {
        return unsafe.getAndSetLong(o, offset, newValue);
    }

    /**
     * Atomically exchanges the given reference value with the current
     * reference value of a field or array element within the given
     * object {@code o} at the given {@code offset}.
     *
     * @param o        object/array to update the field/element in
     * @param offset   field/element offset
     * @param newValue new value
     * @return the previous value
     * @since 1.8
     */
    // @HotSpotIntrinsicCandidate
    @TargetApi(24)
    public Object getAndSetObject(Object o, long offset, Object newValue) {
        return unsafe.getAndSetObject(o, offset, newValue);
    }

    /**
     * Ensures that loads before the fence will not be reordered with loads and
     * stores after the fence; a "LoadLoad plus LoadStore barrier".
     * <p>
     * Corresponds to C11 atomic_thread_fence(memory_order_acquire)
     * (an "acquire fence").
     * <p>
     * A pure LoadLoad fence is not provided, since the addition of LoadStore
     * is almost always desired, and most current hardware instructions that
     * provide a LoadLoad barrier also provide a LoadStore barrier for free.
     *
     * @since 1.8
     */
    // @HotSpotIntrinsicCandidate
    @TargetApi(24)
    public void loadFence() {
        unsafe.loadFence();
    }

    /**
     * Ensures that loads and stores before the fence will not be reordered with
     * stores after the fence; a "StoreStore plus LoadStore barrier".
     * <p>
     * Corresponds to C11 atomic_thread_fence(memory_order_release)
     * (a "release fence").
     * <p>
     * A pure StoreStore fence is not provided, since the addition of LoadStore
     * is almost always desired, and most current hardware instructions that
     * provide a StoreStore barrier also provide a LoadStore barrier for free.
     *
     * @since 1.8
     */
    // @HotSpotIntrinsicCandidate
    @TargetApi(24)
    public void storeFence() {
        unsafe.storeFence();
    }

    /**
     * Ensures that loads and stores before the fence will not be reordered
     * with loads and stores after the fence.  Implies the effects of both
     * loadFence() and storeFence(), and in addition, the effect of a StoreLoad
     * barrier.
     * <p>
     * Corresponds to C11 atomic_thread_fence(memory_order_seq_cst).
     *
     * @since 1.8
     */
    // @HotSpotIntrinsicCandidate
    @TargetApi(24)
    public void fullFence() {
        unsafe.fullFence();
    }
}
```

所以最终问题就变成了如何用Unsafe将classloader设为null，即如下代码中的字段。

```
public final class Class<T> implements java.io.Serializable,
                              GenericDeclaration,
                              Type,
                              AnnotatedElement {
 
 
    /** defining class loader, or null for the "bootstrap" system loader. */
    private transient ClassLoader classLoader;
 
 
}
```


java.lang.Class对象隐式继承自java.lang.Object

```
public class Object {
    private transient Class<?> shadow$_klass_;
    private transient int shadow$_monitor_;
}
```

因此要将classLoader设为null，即需要找到该字段在内存中的偏移地址。

我们通过构造一个和java.lang.Class一样的类，用于辅助找到该偏移地址

```
public class ReflectWrapper {
    //just for finding the java.lang.Class classLoader field's offset
    @Keep
    private Object classLoaderOffsetHelper;
 
}
```

classLoaderOffsetHelper对象的偏移地址就是classLoader的偏移地址，为什么呢？
因为他们都隐式继承自java.lang.Object对象，并且都是该对象的第一个引用类型的字段。

首先反射拿到该字段

```
Field classLoader = ReflectWrapper.class.getDeclaredField("classLoaderOffsetHelper");

```

使用Unsafe得到该字段在内存中的偏移

```
long classLoaderOffset = UnSafeWrapper.getUnSafe().objectFieldOffset(classLoader);

```

校验该偏移指向的地址是否是ClassLoader对象

```
if (UnSafeWrapper.getUnSafe().getObject(ReflectWrapper.class, classLoaderOffset) instanceof ClassLoader) {
    //todo
}
```

将该偏移指向的对象进行替换，设成null

```
Object originalClassLoader = UnSafeWrapper.getUnSafe().getAndSetObject(ReflectWrapper.class, classLoaderOffset, null);

```

完整的代码如下

```
@Keep
public class ReflectWrapper {
 
    //just for finding the java.lang.Class classLoader field's offset
    @Keep
    private Object classLoaderOffsetHelper;
 
    static {
        try {
            Class<?> VersionClass = Class.forName("android.os.Build$VERSION");
            Field sdkIntField = VersionClass.getDeclaredField("SDK_INT");
            sdkIntField.setAccessible(true);
            int sdkInt = sdkIntField.getInt(null);
            if (sdkInt >= 28) {
                Field classLoader = ReflectWrapper.class.getDeclaredField("classLoaderOffsetHelper");
                long classLoaderOffset = UnSafeWrapper.getUnSafe().objectFieldOffset(classLoader);
                if (UnSafeWrapper.getUnSafe().getObject(ReflectWrapper.class, classLoaderOffset) instanceof ClassLoader) {
                    Object originalClassLoader = UnSafeWrapper.getUnSafe().getAndSetObject(ReflectWrapper.class, classLoaderOffset, null);
                } else {
                    throw new RuntimeException("not support");
                }
            }
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
```

之后的事情就变得很简单了，所有反射工作都通过ReflectWrapper进行调用，现在该类就是上帝类，可以为所欲为。

对应实现可以参考

```
package github.io.lizhangqu.reflect;

import android.support.annotation.Keep;

import github.io.lizhangqu.unsafe.UnSafeWrapper;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Arrays;

/**
 * @author lizhangqu
 * @version V1.0
 * @since 2018-06-30 12:30
 */
@Keep
public class ReflectWrapper {

    //just for finding the java.lang.Class classLoader field's offset
    @Keep
    private Object classLoaderOffsetHelper;

    static {
        try {
            Class<?> VersionClass = Class.forName("android.os.Build$VERSION");
            Field sdkIntField = VersionClass.getDeclaredField("SDK_INT");
            sdkIntField.setAccessible(true);
            int sdkInt = sdkIntField.getInt(null);
            if (sdkInt >= 28) {
                Field classLoader = ReflectWrapper.class.getDeclaredField("classLoaderOffsetHelper");
                long classLoaderOffset = UnSafeWrapper.getUnSafe().objectFieldOffset(classLoader);
                if (UnSafeWrapper.getUnSafe().getObject(ReflectWrapper.class, classLoaderOffset) instanceof ClassLoader) {
                    Object originalClassLoader = UnSafeWrapper.getUnSafe().getAndSetObject(ReflectWrapper.class, classLoaderOffset, null);
                } else {
                    throw new RuntimeException("not support");
                }
            }
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    /**
     * Locates a given field anywhere in the class inheritance hierarchy.
     *
     * @param instance an object to search the field into.
     * @param name     field name
     * @return a field object
     * @throws NoSuchFieldException if the field cannot be located
     */
    public static Field findField(Object instance, String name) throws NoSuchFieldException {
        for (Class<?> clazz = instance.getClass(); clazz != null; clazz = clazz.getSuperclass()) {
            try {
                Field field = clazz.getDeclaredField(name);

                if (!field.isAccessible()) {
                    field.setAccessible(true);
                }

                return field;
            } catch (NoSuchFieldException e) {
                // ignore and search next
            }
        }

        throw new NoSuchFieldException("Field " + name + " not found in " + instance.getClass());
    }

    public static Field findField(Class<?> originClazz, String name) throws NoSuchFieldException {
        for (Class<?> clazz = originClazz; clazz != null; clazz = clazz.getSuperclass()) {
            try {
                Field field = clazz.getDeclaredField(name);

                if (!field.isAccessible()) {
                    field.setAccessible(true);
                }

                return field;
            } catch (NoSuchFieldException e) {
                // ignore and search next
            }
        }

        throw new NoSuchFieldException("Field " + name + " not found in " + originClazz);
    }

    /**
     * Locates a given method anywhere in the class inheritance hierarchy.
     *
     * @param instance       an object to search the method into.
     * @param name           method name
     * @param parameterTypes method parameter types
     * @return a method object
     * @throws NoSuchMethodException if the method cannot be located
     */
    public static Method findMethod(Object instance, String name, Class<?>... parameterTypes)
            throws NoSuchMethodException {
        for (Class<?> clazz = instance.getClass(); clazz != null; clazz = clazz.getSuperclass()) {
            try {
                Method method = clazz.getDeclaredMethod(name, parameterTypes);

                if (!method.isAccessible()) {
                    method.setAccessible(true);
                }

                return method;
            } catch (NoSuchMethodException e) {
                // ignore and search next
            }
        }

        throw new NoSuchMethodException("Method "
                + name
                + " with parameters "
                + Arrays.asList(parameterTypes)
                + " not found in " + instance.getClass());
    }

    /**
     * Locates a given method anywhere in the class inheritance hierarchy.
     *
     * @param clazz          a class to search the method into.
     * @param name           method name
     * @param parameterTypes method parameter types
     * @return a method object
     * @throws NoSuchMethodException if the method cannot be located
     */
    public static Method findMethod(Class<?> clazz, String name, Class<?>... parameterTypes)
            throws NoSuchMethodException {
        for (; clazz != null; clazz = clazz.getSuperclass()) {
            try {
                Method method = clazz.getDeclaredMethod(name, parameterTypes);

                if (!method.isAccessible()) {
                    method.setAccessible(true);
                }

                return method;
            } catch (NoSuchMethodException e) {
                // ignore and search next
            }
        }

        throw new NoSuchMethodException("Method "
                + name
                + " with parameters "
                + Arrays.asList(parameterTypes)
                + " not found in " + clazz);
    }

    public static Constructor<?> findConstructor(Class<?> originClazz, Class<?>... parameterTypes) throws NoSuchMethodException {
        for (Class<?> clazz = originClazz; clazz != null; clazz = clazz.getSuperclass()) {
            try {
                Constructor<?> ctor = clazz.getDeclaredConstructor(parameterTypes);

                if (!ctor.isAccessible()) {
                    ctor.setAccessible(true);
                }

                return ctor;
            } catch (NoSuchMethodException e) {
                // ignore and search next
            }
        }

        throw new NoSuchMethodException("Constructor"
                + " with parameters "
                + Arrays.asList(parameterTypes)
                + " not found in " + originClazz);
    }

    /**
     * Locates a given constructor anywhere in the class inheritance hierarchy.
     *
     * @param instance       an object to search the constructor into.
     * @param parameterTypes constructor parameter types
     * @return a constructor object
     * @throws NoSuchMethodException if the constructor cannot be located
     */
    public static Constructor<?> findConstructor(Object instance, Class<?>... parameterTypes)
            throws NoSuchMethodException {
        for (Class<?> clazz = instance.getClass(); clazz != null; clazz = clazz.getSuperclass()) {
            try {
                Constructor<?> ctor = clazz.getDeclaredConstructor(parameterTypes);

                if (!ctor.isAccessible()) {
                    ctor.setAccessible(true);
                }

                return ctor;
            } catch (NoSuchMethodException e) {
                // ignore and search next
            }
        }

        throw new NoSuchMethodException("Constructor"
                + " with parameters "
                + Arrays.asList(parameterTypes)
                + " not found in " + instance.getClass());
    }
}
```
