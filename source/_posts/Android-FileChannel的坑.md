title: Android FileChannel的坑
date: 2017-11-06 14:12:17
categories: [Android]
tags: [Android, FileChannel]
---

为了偷懒，使用了nio中的FileChannel进行流的读取，代码如下：

```
long transferSize = toChannel.transferFrom(fromChannel, 0, Long.MAX_VALUE);
```

<!-- more -->

解释一下为什么这里第三个参数用Long.MAX_VALUE，因为代码上下文中，这个值具备不确定性，自己得到的值可能是-1，也可能是正确的值，为了简单起见，传递一个最大值进去，transferFrom内部会有一个Math.min操作（7.0以上的代码），取这个值和真正的大小中小的那个。

写个单元测试测一下，完美，没有任何问题。

某一天，同事跑过来说这段读取逻辑有问题，报了一个异常

```
java.lang.IllegalArgumentException: position=0 count=9223372036854775807
```

然后我又测了下，在自己的手机上跑一下，没问题，再在pc上跑一下单元测试，也没问题。但是同事那边是有问题的，于是怀疑和系统版本有关系，仔细排查了一下，确实是这样，Android 7.0以上没问题，Android 7.0以下全部阵亡。


翻下AOSP的代码

 - [Android 6.0的实现](https://android.googlesource.com/platform/libcore/+/android-cts-6.0_r24/luni/src/main/java/java/nio/FileChannelImpl.java)
 - [Android 7.0的实现](https://android.googlesource.com/platform/libcore/+/android-cts-7.0_r15/ojluni/src/main/java/sun/nio/ch/FileChannelImpl.java)

 那么实现有什么差异呢，先看7.0以下的实现，这里以6.0为例

 ```
 public long transferFrom(ReadableByteChannel src, long position, long count) throws IOException {
    checkOpen();
    if (!src.isOpen()) {
        throw new ClosedChannelException();
    }
    checkWritable();
    if (position < 0 || count < 0 || count > Integer.MAX_VALUE) {
        throw new IllegalArgumentException("position=" + position + " count=" + count);
    }
    if (position > size()) {
        return 0;
    }
    // Although sendfile(2) originally supported writing to a regular file.
    // In Linux 2.6 and later, it only supports writing to sockets.
    // If our source is a regular file, mmap(2) rather than reading.
    // Callers should only be using transferFrom for large transfers,
    // so the mmap(2) overhead isn't a concern.
    if (src instanceof FileChannel) {
        FileChannel fileSrc = (FileChannel) src;
        long size = fileSrc.size();
        long filePosition = fileSrc.position();
        count = Math.min(count, size - filePosition);
        ByteBuffer buffer = fileSrc.map(MapMode.READ_ONLY, filePosition, count);
        try {
            fileSrc.position(filePosition + count);
            return write(buffer, position);
        } finally {
            NioUtils.freeDirectBuffer(buffer);
        }
    }
    // For non-file channels, all we can do is read and write via userspace.
    ByteBuffer buffer = ByteBuffer.allocate((int) count);
    src.read(buffer);
    buffer.flip();
    return write(buffer, position);
}
 ```

擦，入参count是Long类型，竟然校验的时候用int的最大值去校验，元凶就在这里了

```
 if (position < 0 || count < 0 || count > Integer.MAX_VALUE) {
    throw new IllegalArgumentException("position=" + position + " count=" + count);
}
```

那么看看7.0以上为什么没有报错

```
public long transferFrom(ReadableByteChannel src,
                         long position, long count)
    throws IOException
{
    ensureOpen();
    if (!src.isOpen())
        throw new ClosedChannelException();
    if (!writable)
        throw new NonWritableChannelException();
    if ((position < 0) || (count < 0))
        throw new IllegalArgumentException();
    if (position > size())
        return 0;
    if (src instanceof FileChannelImpl)
       return transferFromFileChannel((FileChannelImpl)src,
                                      position, count);
    return transferFromArbitraryChannel(src, position, count);
}
```

没毛病，没有对count的最大值进行校验，自然不会抛异常。

那么PC上的单元测试为什么没有报错呢，因为自己电脑上的JDK是1.8的版本，PC上的实现和Android 7.0的实现是一样的，都是基于Java8实现的，自然也测不出问题。

最后这个问题怎么解决呢，不能偷懒，改成buffer读取

```
ByteBuffer buffer = ByteBuffer.allocate(4096);
while (fromChannel.read(buffer) != -1) {
    buffer.flip();
    transferSize += toChannel.write(buffer);
    buffer.clear();
}
```

还有一种解决方法就是传递具体的大小进去，前提是你知道具体的大小

```
long transferSize = toChannel.transferFrom(fromChannel, 0, 具体的大小);
```
