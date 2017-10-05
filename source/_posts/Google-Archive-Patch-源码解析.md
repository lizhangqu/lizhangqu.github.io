title: Google Archive Patch 源码解析
date: 2017-10-05 09:20:15
categories: [Android]
tags: [bspatch, bsdiff, archive patch, android, delta]
---

如果你觉得本篇文章太长，可以直接看我总结的结论：

>Google Archive Patch是严格的基于Zip文件格式的差量算法，其核心生成差量的算法还是BsDiff，核心合成文件的算法还是BsPatch，只是它将旧Zip文件和新Zip文件里的内容解压出来分别转为了差量友好的一个文件，使用差量算法生成差量文件；合成时，将旧Zip文件里的内容解压出来转为差量友好的一个文件，应用合成算法，生成新文件的差量友好的一个文件，再利用patch文件中每个ZipEntry的偏移和长度，以及压缩等级，编码策略，nowrap等标记，将其恢复为Zip文件。之所以使用差量友好的文件是因为一个文件，如果未压缩，那么可以很简单的描述其变化，如字符串"abc"，变为了"abcd"，我们可以直观的描述其变化，增加了一个字符"d"；但是如果字符串经过了压缩，那么这个变化不再可以这么容易的被描述。因此需要将压缩后的文件转为未压缩的文件，生成差量友好的文件。
>
>生成慢：Google Archive Patch之所以生成Patch的时间变长了，是因为Zip文件解压出来后，生成的差量友好的文件变大了，因此使用BsDiff时，耗费的时间变长了。比如解压出来后变大了2倍，则时间消耗变为了原来整个文件的生成差量的时间的2倍。
>
>合成慢：合成的时间变长了，一方面的消耗也是因为生成差量友好的文件变大了，但是这不是本质原因，BsPatch合成是极快的，就算double倍时间，这点时间也是可以忽略不计的。其耗费时间的根本问题还在于重新生成zip文件时需要对流做各种判断操作，一部分数据需要压缩，一部分数据需要拷贝，基本上大部分的耗时操作都花在了数据的压缩操作上。
>
>生成文件小：小的原因上面已经解释过了，是因为基于差量友好的文件生成差量文件的，文件间的变换变得很容易描述。

<!-- more -->

### 项目地址

[Google Archive Patch](https://github.com/andrewhayden/archive-patcher)

主要看三个模块，一个是shared，一个是generator，另一个是applier。shared为另外两个的公共模块，generator为差量生成模块，applier为差量应用模块，其中generator中实现了一份java版的bsdiff算法，applier中实现了一份java版的bspatch算法。

### Zip文件格式

Google Archive Patch是严格基于Zip文件格式的差量算法，因此有必要了解一下Zip文件格式。参考了网上的几篇文章，发现其介绍文件格式的时候犯了一个小问题，他们都是正序的介绍其构成，但是其实应该倒过来，这样更加便于理解。

一个Zip文件一般有三段构成

![zip-format.png](zip-format.png)

我们一一来解释这三段，首先看最后一段

#### End of Central Directory

| Offset | Bytes | Description                              | 备注                   |
| ------ | ----- | ---------------------------------------- | -------------------- |
| 0      | 4     | End of Central Directory SIGNATURE = 0x06054b50 | 区块头部标记，固定值0x06054b50 |
| 4      | 2     | disk number for this archive             | 忽略                   |
| 6      | 2     | disk number for the central directory    | 忽略                   |
| 8      | 2     | num entries in the central directory on this disk | 忽略                   |
| 10     | 2     | num entries in the central directory overall | 核心目录结构总数             |
| 12     | 4     | the length of the central directory      | 核心目录的大小              |
| 16     | 4     | the file offset of the central directory | 核心目录的偏移              |
| 20     | 2     | the length of the zip file comment       | 注释长度                 |
| 22     | n     | from here to the EOF is the zip file comment | 注释内容                 |

该段由一个表格所示的结构构成。这段的作用就是为了找出Central Directory的位置。

#### Central Directory

由End of Central Directory可以索引出Central Directory，看看其构成。

| Offset | Bytes | Description                              | 备注                   |
| ------ | ----- | ---------------------------------------- | -------------------- |
| 0      | 4     | Central Directory SIGNATURE = 0x02014b50 | 区块头部标记，固定值0x02014b50 |
| 4      | 2     | the version-made-by                      | 忽略                   |
| 6      | 2     | the version-needed-to-extract            | 忽略                   |
| 8      | 2     | the general-purpose flags, read for language encoding | 通用位标记                |
| 10     | 2     | the compression method                   | 压缩方法                 |
| 12     | 2     | the MSDOS last modified file time        | 文件最后修改时间             |
| 14     | 2     | the MSDOS last modified file date        | 文件最后修改日期             |
| 16     | 4     | the CRC32 of the uncompressed data       | crc32校验码             |
| 20     | 4     | the compressed size                      | 压缩后的大小               |
| 24     | 4     | the uncompressed size                    | 未压缩的大小               |
| 28     | 2     | the length of the file name              | 文件名长度                |
| 30     | 2     | the length of the extras                 | 扩展域长度                |
| 32     | 2     | the length of the comment                | 文件注释长度               |
| 34     | 2     | the disk number                          | 忽略                   |
| 36     | 2     | the internal file attributes             | 忽略                   |
| 38     | 4     | the external file attributes             | 忽略                   |
| 42     | 4     | the offset of the local section entry, where the data is | local entry所在偏移      |
| 46     | i     | the file name                            | 文件名                  |
| 46+i   | j     | the extras                               | 扩展域                  |
| 46+i+j | k     | the comment                              | 文件注释                 |

该段由n个表格表示的结构构成。这段的作用就是为了找出Zip文件真实数据所在的位置。

#### Contents of ZIP entries

由Central Directory段可以索引出Local Entry段，最后看一下Local Entry段

| Offset | Bytes | Description                        | 备注                   |
| ------ | ----- | ---------------------------------- | -------------------- |
| 0      | 4     | Local Entry SIGNATURE = 0x04034b50 | 区块头部标记，固定值0x04034b50 |
| 4      | 2     | the version-needed-to-extract      | 忽略                   |
| 6      | 2     | the general-purpose flags          | 通用位标记                |
| 8      | 2     | the compression method             | 压缩方法                 |
| 10     | 2     | the MSDOS last modified file time  | 文件最后修改时间             |
| 12     | 2     | the MSDOS last modified file date  | 文件最后修改日期             |
| 14     | 4     | the CRC32 of the uncompressed data | crc32校验码             |
| 18     | 4     | the compressed size                | 压缩后的大小               |
| 22     | 4     | the uncompressed size              | 未压缩的大小               |
| 26     | 2     | the length of the file name        | 文件名长度                |
| 28     | 2     | the length of the extras           | 扩展域长度                |
| 30     | i     | the file name                      | 文件名                  |
| 30+i   | j     | the extras                         | 扩展区                  |
| 30+i+j | k     | file data                          | 真实压缩数据所在位置           |

该段由n个表格表示的结构构成。

#### Google Archive Patch解析Zip文件代码

Google Archive Patch内部实现了一个解析Zip文件的mini结构，解析的工作主要由com.google.archivepatcher.generator.MinimalZipParser类负责，承载解析出来的数据主要由MinimalCentralDirectoryMetadata、MinimalZipArchive和MinimalZipEntry负责。解析完成后，最终输出的是一个按照偏移量排序的MinimalZipEntry列表。

```java
private static List<MinimalZipEntry> listEntriesInternal(RandomAccessFileInputStream in)
      throws IOException {
    // Step 1: Locate the end-of-central-directory record header.
    long offsetOfEocd = MinimalZipParser.locateStartOfEocd(in, 32768);
    if (offsetOfEocd == -1) {
      // Archive is weird, abort.
      throw new ZipException("EOCD record not found in last 32k of archive, giving up");
    }

    // Step 2: Parse the end-of-central-directory data to locate the central directory itself
    in.setRange(offsetOfEocd, in.length() - offsetOfEocd);
    MinimalCentralDirectoryMetadata centralDirectoryMetadata = MinimalZipParser.parseEocd(in);

    // Step 3: Extract a list of all central directory entries (contiguous data stream)
    in.setRange(
        centralDirectoryMetadata.getOffsetOfCentralDirectory(),
        centralDirectoryMetadata.getLengthOfCentralDirectory());
    List<MinimalZipEntry> minimalZipEntries =
        new ArrayList<MinimalZipEntry>(centralDirectoryMetadata.getNumEntriesInCentralDirectory());
    for (int x = 0; x < centralDirectoryMetadata.getNumEntriesInCentralDirectory(); x++) {
      minimalZipEntries.add(MinimalZipParser.parseCentralDirectoryEntry(in));
    }

    // Step 4: Sort the entries in file order, not central directory order.
    Collections.sort(minimalZipEntries, LOCAL_ENTRY_OFFSET_COMAPRATOR);

    // Step 5: Seek out each local entry and calculate the offset of the compressed data within
    for (int x = 0; x < minimalZipEntries.size(); x++) {
      MinimalZipEntry entry = minimalZipEntries.get(x);
      long offsetOfNextEntry;
      if (x < minimalZipEntries.size() - 1) {
        // Don't allow reading past the start of the next entry, for sanity.
        offsetOfNextEntry = minimalZipEntries.get(x + 1).getFileOffsetOfLocalEntry();
      } else {
        // Last entry. Don't allow reading into the central directory, for sanity.
        offsetOfNextEntry = centralDirectoryMetadata.getOffsetOfCentralDirectory();
      }
      long rangeLength = offsetOfNextEntry - entry.getFileOffsetOfLocalEntry();
      in.setRange(entry.getFileOffsetOfLocalEntry(), rangeLength);
      long relativeDataOffset = MinimalZipParser.parseLocalEntryAndGetCompressedDataOffset(in);
      entry.setFileOffsetOfCompressedData(entry.getFileOffsetOfLocalEntry() + relativeDataOffset);
    }

    // Done!
    return minimalZipEntries;
  }
```

以上代码主要做了下面几件事

- 定位End of Central Directory起始偏移量
- 找到Central Directory段
- 解析Central Directory段
- 排序，按照偏移量升序
- 解析真实数据，找到其偏移量

如何定位End of Central Directory起始偏移量，其实很简单，扫描字节，找到特定的头部，即0x06054b50，其内部实现是扫描zip文件的最后32k部分的字节数组，找到了就返回，找不到就抛异常。这里有一个问题，如果最后32k找不到怎么办，找了相关资料，也没找到End of Central Directory一定在最后32k的说法，翻了Android Multidex的实现，发现它扫描的是最后64k的字节，这里就姑且认为它一定能扫描得到吧。其实现如下：

```java
public static long locateStartOfEocd(RandomAccessFileInputStream in, int searchBufferLength)
      throws IOException {
    final int maxBufferSize = (int) Math.min(searchBufferLength, in.length());
    final byte[] buffer = new byte[maxBufferSize];//32k
    final long rangeStart = in.length() - buffer.length;
    in.setRange(rangeStart, buffer.length);
    readOrDie(in, buffer, 0, buffer.length);//read to buffer
    int offset = locateStartOfEocd(buffer);//locate
    if (offset == -1) {
      return -1;
    }
    return rangeStart + offset;
  }

  public static int locateStartOfEocd(byte[] buffer) {
    int last4Bytes = 0; // This is the 32 bits of data from the file
    for (int offset = buffer.length - 1; offset >= 0; offset--) {
      last4Bytes <<= 8;
      last4Bytes |= buffer[offset];
      if (last4Bytes == EOCD_SIGNATURE) {//0x06054b50
        return offset;
      }
    }
    return -1;
  }
```

找到End of Central Directory的起始偏移位置之后，就是解析该段数据，返回MinimalCentralDirectoryMetadata数据结构了。解析代码如下：

```java
public static MinimalCentralDirectoryMetadata parseEocd(InputStream in)
      throws IOException, ZipException {
    if (((int) read32BitUnsigned(in)) != EOCD_SIGNATURE) {//0x06054b50
      throw new ZipException("Bad eocd header");
    }

    // *** 4 bytes encode EOCD_SIGNATURE, ignore (already found and verified).
    // 2 bytes encode disk number for this archive, ignore.
    // 2 bytes encode disk number for the central directory, ignore.
    // 2 bytes encode num entries in the central directory on this disk, ignore.
    // *** 2 bytes encode num entries in the central directory overall [READ THIS]
    // *** 4 bytes encode the length of the central directory [READ THIS]
    // *** 4 bytes encode the file offset of the central directory [READ THIS]
    // 2 bytes encode the length of the zip file comment, ignore.
    // Everything else from here to the EOF is the zip file comment, or junk. Ignore.
    skipOrDie(in, 2 + 2 + 2);
    int numEntriesInCentralDirectory = read16BitUnsigned(in);//number
    if (numEntriesInCentralDirectory == 0xffff) {
      // If 0xffff, this is a zip64 archive and this code doesn't handle that.
      throw new ZipException("No support for zip64");
    }
    long lengthOfCentralDirectory = read32BitUnsigned(in);//length
    long offsetOfCentralDirectory = read32BitUnsigned(in);//offset
    return new MinimalCentralDirectoryMetadata(
        numEntriesInCentralDirectory, offsetOfCentralDirectory, lengthOfCentralDirectory);
  }
```

从代码中可以看出，其实只是解析出了三个重要的数据，分别是:

- Central Directory 个数 n
- Central Directory起始偏移 offset
- Central Directory总长度 length

之后就是锁定数据区域在[offset,offest+length]，内部实现是RandomAccessFile。for循环，循环次数为n，依次解析各个Central Directory。其解析单个Central Directory的代码如下：

```Java
public static MinimalZipEntry parseCentralDirectoryEntry(InputStream in) throws IOException {
    // *** 4 bytes encode the CENTRAL_DIRECTORY_ENTRY_SIGNATURE, verify for sanity
    // 2 bytes encode the version-made-by, ignore
    // 2 bytes encode the version-needed-to-extract, ignore
    // *** 2 bytes encode the general-purpose flags, read for language encoding. [READ THIS]
    // *** 2 bytes encode the compression method, [READ THIS]
    // 2 bytes encode the MSDOS last modified file time, ignore
    // 2 bytes encode the MSDOS last modified file date, ignore
    // *** 4 bytes encode the CRC32 of the uncompressed data [READ THIS]
    // *** 4 bytes encode the compressed size [READ THIS]
    // *** 4 bytes encode the uncompressed size [READ THIS]
    // *** 2 bytes encode the length of the file name [READ THIS]
    // *** 2 bytes encode the length of the extras, needed to skip the bytes later [READ THIS]
    // *** 2 bytes encode the length of the comment, needed to skip the bytes later [READ THIS]
    // 2 bytes encode the disk number, ignore
    // 2 bytes encode the internal file attributes, ignore
    // 4 bytes encode the external file attributes, ignore
    // *** 4 bytes encode the offset of the local section entry, where the data is [READ THIS]
    // n bytes encode the file name
    // n bytes encode the extras
    // n bytes encode the comment
    if (((int) read32BitUnsigned(in)) != CENTRAL_DIRECTORY_ENTRY_SIGNATURE) {
      throw new ZipException("Bad central directory header");
    }
    skipOrDie(in, 2 + 2); // Skip version stuff
    int generalPurposeFlags = read16BitUnsigned(in);
    int compressionMethod = read16BitUnsigned(in);
    skipOrDie(in, 2 + 2); // Skip MSDOS junk
    long crc32OfUncompressedData = read32BitUnsigned(in);
    long compressedSize = read32BitUnsigned(in);
    long uncompressedSize = read32BitUnsigned(in);
    int fileNameLength = read16BitUnsigned(in);
    int extrasLength = read16BitUnsigned(in);
    int commentLength = read16BitUnsigned(in);
    skipOrDie(in, 2 + 2 + 4); // Skip the disk number and file attributes
    long fileOffsetOfLocalEntry = read32BitUnsigned(in);
    byte[] fileNameBuffer = new byte[fileNameLength];
    readOrDie(in, fileNameBuffer, 0, fileNameBuffer.length);
    skipOrDie(in, extrasLength + commentLength);
    // General purpose flag bit 11 is an important hint for the character set used for file names.
    boolean generalPurposeFlagBit11 = (generalPurposeFlags & (0x1 << 10)) != 0;
    return new MinimalZipEntry(
        compressionMethod,
        crc32OfUncompressedData,
        compressedSize,
        uncompressedSize,
        fileNameBuffer,
        generalPurposeFlagBit11,
        fileOffsetOfLocalEntry);
  }
```

主要解析出如下的数据：

- 压缩方法
- crc32校验码
- 压缩前大小
- 压缩后大小
- 文件名
- 通用标记位
- local entry偏移位置offset



返回了一个list，里面有n个MinimalZipEntry结构，经过按offset升序排序后，再遍历list，解析其在local entry中的真实数据的偏移，其解析代码如下：

```java
public static long parseLocalEntryAndGetCompressedDataOffset(InputStream in) throws IOException {
    // *** 4 bytes encode the LOCAL_ENTRY_SIGNATURE, verify for sanity
    // 2 bytes encode the version-needed-to-extract, ignore
    // 2 bytes encode the general-purpose flags, ignore
    // 2 bytes encode the compression method, ignore (redundant with central directory)
    // 2 bytes encode the MSDOS last modified file time, ignore
    // 2 bytes encode the MSDOS last modified file date, ignore
    // 4 bytes encode the CRC32 of the uncompressed data, ignore (redundant with central directory)
    // 4 bytes encode the compressed size, ignore (redundant with central directory)
    // 4 bytes encode the uncompressed size, ignore (redundant with central directory)
    // *** 2 bytes encode the length of the file name, needed to skip the bytes later [READ THIS]
    // *** 2 bytes encode the length of the extras, needed to skip the bytes later [READ THIS]
    // The rest is the data, which is the main attraction here.
    if (((int) read32BitUnsigned(in)) != LOCAL_ENTRY_SIGNATURE) {
      throw new ZipException("Bad local entry header");
    }
    int junkLength = 2 + 2 + 2 + 2 + 2 + 4 + 4 + 4;
    skipOrDie(in, junkLength); // Skip everything up to the length of the file name
    final int fileNameLength = read16BitUnsigned(in);
    final int extrasLength = read16BitUnsigned(in);

    // The file name is already known and will match the central directory, so no need to read it.
    // The extra field length can be different here versus in the central directory and is used for
    // things like zipaligning APKs. This single value is the critical part as it dictates where the
    // actual DATA for the entry begins.
    return 4 + junkLength + 2 + 2 + fileNameLength + extrasLength;
  }
```

很简单，跳过了locat entry的真实数据前面的所有字节，获得偏移。

至此Zip文件解析完成。



### 差量文件的生成

实现代码主要在FileByFileV1DeltaGenerator中，代码如下：

```java
  @Override
  public void generateDelta(File oldFile, File newFile, OutputStream patchOut)
      throws IOException, InterruptedException {
    try (TempFileHolder deltaFriendlyOldFile = new TempFileHolder();
        TempFileHolder deltaFriendlyNewFile = new TempFileHolder();
        TempFileHolder deltaFile = new TempFileHolder();
        FileOutputStream deltaFileOut = new FileOutputStream(deltaFile.file);
        BufferedOutputStream bufferedDeltaOut = new BufferedOutputStream(deltaFileOut)) {
      PreDiffExecutor.Builder builder =
          new PreDiffExecutor.Builder()
              .readingOriginalFiles(oldFile, newFile)
              .writingDeltaFriendlyFiles(deltaFriendlyOldFile.file, deltaFriendlyNewFile.file);
      for (RecommendationModifier modifier : recommendationModifiers) {
        builder.withRecommendationModifier(modifier);
      }
      PreDiffExecutor executor = builder.build();
      PreDiffPlan preDiffPlan = executor.prepareForDiffing();
      DeltaGenerator deltaGenerator = getDeltaGenerator();
      deltaGenerator.generateDelta(
          deltaFriendlyOldFile.file, deltaFriendlyNewFile.file, bufferedDeltaOut);
      bufferedDeltaOut.close();
      PatchWriter patchWriter =
          new PatchWriter(
              preDiffPlan,
              deltaFriendlyOldFile.file.length(),
              deltaFriendlyNewFile.file.length(),
              deltaFile.file);
      patchWriter.writeV1Patch(patchOut);
    }
  }
  protected DeltaGenerator getDeltaGenerator() {
    return new BsDiffDeltaGenerator();
  }
```

干了如下几件事:

- 生成了三个临时文件，分别用于存储旧文件的差量友好文件，新文件的差量友好文件，差量文件，这三个文件会在jvm退出时自动删除。
- 调用PreDiffExecutor的prepareForDiffing生成PreDiffPlan对象，该函数做了很多很多十分复杂的事情，后面细说
- 应用BsDiff差量算法生成差量文件
- 生成patch文件，patch文件格式后面细说。

现在来看下PreDiffExecutor的prepareForDiffing函数：

```java
  public PreDiffPlan prepareForDiffing() throws IOException {
    PreDiffPlan preDiffPlan = generatePreDiffPlan();
    List<TypedRange<JreDeflateParameters>> deltaFriendlyNewFileRecompressionPlan = null;
    if (deltaFriendlyOldFile != null) {
      // Builder.writingDeltaFriendlyFiles() ensures old and new are non-null when called, so a
      // check on either is sufficient.
      deltaFriendlyNewFileRecompressionPlan =
          Collections.unmodifiableList(generateDeltaFriendlyFiles(preDiffPlan));
    }
    return new PreDiffPlan(
        preDiffPlan.getQualifiedRecommendations(),
        preDiffPlan.getOldFileUncompressionPlan(),
        preDiffPlan.getNewFileUncompressionPlan(),
        deltaFriendlyNewFileRecompressionPlan);
  }
```

干了下面几件事：

- 调用generatePreDiffPlan函数，生成一个PreDiffPlan对象，这个函数后面细说
- 根据返回的PreDiffPlan对象，调用generateDeltaFriendlyFiles函数生成差量友好文件，这个函数后面细说
- 创建一个PreDiffPlan对象，将相关参数传入，分别是建议列表，旧文件需要被解压的列表，新闻需要被解压的列表，还有生成的新文件的差量友好相关的列表

现在来看看generatePreDiffPlan函数：

```Java
  private PreDiffPlan generatePreDiffPlan() throws IOException {
    Map<ByteArrayHolder, MinimalZipEntry> originalOldArchiveZipEntriesByPath =
        new HashMap<ByteArrayHolder, MinimalZipEntry>();
    Map<ByteArrayHolder, MinimalZipEntry> originalNewArchiveZipEntriesByPath =
        new HashMap<ByteArrayHolder, MinimalZipEntry>();
    Map<ByteArrayHolder, JreDeflateParameters> originalNewArchiveJreDeflateParametersByPath =
        new HashMap<ByteArrayHolder, JreDeflateParameters>();

    for (MinimalZipEntry zipEntry : MinimalZipArchive.listEntries(originalOldFile)) {
      ByteArrayHolder key = new ByteArrayHolder(zipEntry.getFileNameBytes());
      originalOldArchiveZipEntriesByPath.put(key, zipEntry);
    }

    DefaultDeflateCompressionDiviner diviner = new DefaultDeflateCompressionDiviner();
    for (DivinationResult divinationResult : diviner.divineDeflateParameters(originalNewFile)) {
      ByteArrayHolder key =
          new ByteArrayHolder(divinationResult.minimalZipEntry.getFileNameBytes());
      originalNewArchiveZipEntriesByPath.put(key, divinationResult.minimalZipEntry);
      originalNewArchiveJreDeflateParametersByPath.put(key, divinationResult.divinedParameters);
    }

    PreDiffPlanner preDiffPlanner =
        new PreDiffPlanner(
            originalOldFile,
            originalOldArchiveZipEntriesByPath,
            originalNewFile,
            originalNewArchiveZipEntriesByPath,
            originalNewArchiveJreDeflateParametersByPath,
            recommendationModifiers.toArray(new RecommendationModifier[] {}));
    return preDiffPlanner.generatePreDiffPlan();
  }

  public List<DivinationResult> divineDeflateParameters(File archiveFile) throws IOException {
    List<DivinationResult> results = new ArrayList<>();
    for (MinimalZipEntry minimalZipEntry : MinimalZipArchive.listEntries(archiveFile)) {
      JreDeflateParameters divinedParameters = null;
      if (minimalZipEntry.isDeflateCompressed()) {
        // TODO(pasc): Reuse streams to avoid churning file descriptors
        MultiViewInputStreamFactory isFactory =
            new RandomAccessFileInputStreamFactory(
                archiveFile,
                minimalZipEntry.getFileOffsetOfCompressedData(),
                minimalZipEntry.getCompressedSize());

        // Keep small entries in memory to avoid unnecessary file I/O.
        if (minimalZipEntry.getCompressedSize() < (100 * 1024)) {
          try (InputStream is = isFactory.newStream()) {
            byte[] compressedBytes = new byte[(int) minimalZipEntry.getCompressedSize()];
            is.read(compressedBytes);
            divinedParameters =
                divineDeflateParameters(new ByteArrayInputStreamFactory(compressedBytes));
          } catch (Exception ignore) {
            divinedParameters = null;
          }
        } else {
          divinedParameters = divineDeflateParameters(isFactory);
        }
      }
      results.add(new DivinationResult(minimalZipEntry, divinedParameters));
    }
    return results;
  }

  public JreDeflateParameters divineDeflateParameters(
      MultiViewInputStreamFactory compressedDataInputStreamFactory) throws IOException {
    byte[] copyBuffer = new byte[32 * 1024];
    // Iterate over all relevant combinations of nowrap, strategy and level.
    for (boolean nowrap : new boolean[] {true, false}) {
      Inflater inflater = new Inflater(nowrap);
      Deflater deflater = new Deflater(0, nowrap);

      strategy_loop:
      for (int strategy : new int[] {0, 1, 2}) {
        deflater.setStrategy(strategy);
        for (int level : LEVELS_BY_STRATEGY.get(strategy)) {
          deflater.setLevel(level);
          inflater.reset();
          deflater.reset();
          try {
            if (matches(inflater, deflater, compressedDataInputStreamFactory, copyBuffer)) {
              end(inflater, deflater);
              return JreDeflateParameters.of(level, strategy, nowrap);
            }
          } catch (ZipException e) {
            // Parse error in input. The only possibilities are corruption or the wrong nowrap.
            // Skip all remaining levels and strategies.
            break strategy_loop;
          }
        }
      }
      end(inflater, deflater);
    }
    return null;
  }
```

generatePreDiffPlan做的事情是生成三个map对象。

- 第一个map对象是持有旧文件的相关数据。key为Zip Entry的文件名对应的字节数组的holder类ByteArrayHolder，value为MinimalZipEntry。
- 第二个map对象的持有新文件的相关数据。key为Zip Entry的文件名对应的字节数组的holder类ByteArrayHolder，value为MinimalZipEntry。
- 第三个map数据就是持有推测出来的新文件的Zip Entry的压缩级别，策略，是否是nowrap三个数据。key为Zip Entry的文件名对应的字节数组的holder类ByteArrayHolder，value为JreDeflateParameters

对于前两个数据调用前面解析过的Zip文件结构相关函数，返回MinimalZipEntry的List类型，key就来自MinimalZipEntry.getFileNameBytes()，而值就是其本身。

而第三个数据来的比较艰辛，需要经过推测，推测的方法很暴力，三层for循环，将压缩的数据解压缩，再利用三个参数的排列组合，即level，strategy，nowrap排列，进行重新压缩，压缩后的数据如果等于从Zip中解析出来的压缩数据，则得到对应的level，strategy，nowrap值。这三个值的承载方式就是JreDeflateParameters。

利用这三个map构建了一个PreDiffPlanner对象，调用该对象的generatePreDiffPlan方法返回PreDiffPlan，其代码如下：

```Java
  PreDiffPlan generatePreDiffPlan() throws IOException {
    List<QualifiedRecommendation> recommendations = getDefaultRecommendations();
    for (RecommendationModifier modifier : recommendationModifiers) {
      // Allow changing the recommendations base on arbitrary criteria.
      recommendations = modifier.getModifiedRecommendations(oldFile, newFile, recommendations);
    }

    // Process recommendations to extract ranges for decompression & recompression
    Set<TypedRange<Void>> oldFilePlan = new HashSet<>();
    Set<TypedRange<JreDeflateParameters>> newFilePlan = new HashSet<>();
    for (QualifiedRecommendation recommendation : recommendations) {
      if (recommendation.getRecommendation().uncompressOldEntry) {
        long offset = recommendation.getOldEntry().getFileOffsetOfCompressedData();
        long length = recommendation.getOldEntry().getCompressedSize();
        TypedRange<Void> range = new TypedRange<Void>(offset, length, null);
        oldFilePlan.add(range);
      }
      if (recommendation.getRecommendation().uncompressNewEntry) {
        long offset = recommendation.getNewEntry().getFileOffsetOfCompressedData();
        long length = recommendation.getNewEntry().getCompressedSize();
        JreDeflateParameters newJreDeflateParameters =
            newArchiveJreDeflateParametersByPath.get(
                new ByteArrayHolder(recommendation.getNewEntry().getFileNameBytes()));
        TypedRange<JreDeflateParameters> range =
            new TypedRange<JreDeflateParameters>(offset, length, newJreDeflateParameters);
        newFilePlan.add(range);
      }
    }

    List<TypedRange<Void>> oldFilePlanList = new ArrayList<>(oldFilePlan);
    Collections.sort(oldFilePlanList);
    List<TypedRange<JreDeflateParameters>> newFilePlanList = new ArrayList<>(newFilePlan);
    Collections.sort(newFilePlanList);
    return new PreDiffPlan(
        Collections.unmodifiableList(recommendations),
        Collections.unmodifiableList(oldFilePlanList),
        Collections.unmodifiableList(newFilePlanList));
  }

  private List<QualifiedRecommendation> getDefaultRecommendations() throws IOException {
    List<QualifiedRecommendation> recommendations = new ArrayList<>();

    // This will be used to find files that have been renamed, but not modified. This is relatively
    // cheap to construct as it just requires indexing all entries by the uncompressed CRC32, and
    // the CRC32 is already available in the ZIP headers.
    SimilarityFinder trivialRenameFinder =
        new Crc32SimilarityFinder(oldFile, oldArchiveZipEntriesByPath.values());

    // Iterate over every pair of entries and get a recommendation for what to do.
    for (Map.Entry<ByteArrayHolder, MinimalZipEntry> newEntry :
        newArchiveZipEntriesByPath.entrySet()) {
      ByteArrayHolder newEntryPath = newEntry.getKey();
      MinimalZipEntry oldZipEntry = oldArchiveZipEntriesByPath.get(newEntryPath);
      if (oldZipEntry == null) {
        // The path is only present in the new archive, not in the old archive. Try to find a
        // similar file in the old archive that can serve as a diff base for the new file.
        List<MinimalZipEntry> identicalEntriesInOldArchive =
            trivialRenameFinder.findSimilarFiles(newFile, newEntry.getValue());
        if (!identicalEntriesInOldArchive.isEmpty()) {
          // An identical file exists in the old archive at a different path. Use it for the
          // recommendation and carry on with the normal logic.
          // All entries in the returned list are identical, so just pick the first one.
          // NB, in principle it would be optimal to select the file that required the least work
          // to apply the patch - in practice, it is unlikely that an archive will contain multiple
          // copies of the same file that are compressed differently, so don't bother with that
          // degenerate case.
          oldZipEntry = identicalEntriesInOldArchive.get(0);
        }
      }

      // If the attempt to find a suitable diff base for the new entry has failed, oldZipEntry is
      // null (nothing to do in that case). Otherwise, there is an old entry that is relevant, so
      // get a recommendation for what to do.
      if (oldZipEntry != null) {
        recommendations.add(getRecommendation(oldZipEntry, newEntry.getValue()));
      }
    }
    return recommendations;
  }
```

该函数主要生成两个List对象，分别是：

- 旧文件的建议解压的Zip Entry的压缩数据偏移位置和数据长度，承载的载体是TypedRange，泛型是Void，所有相关文件组成一个List对象
- 新文件的建议解压的Zip Entry的压缩数据的偏移位置和数据长度，承载的载体是TypedRange，泛型是JreDeflateParameters，泛型参数对应的值来自上一步解析出来的第三个map，所有相关件组成一个List对象

上面两个List对象各自按偏移升序排序。

上面提到建议解压的Zip Entry，那么这个数据是怎么来的呢？来自下面这个函数

```java
  private List<QualifiedRecommendation> getDefaultRecommendations() throws IOException {
    List<QualifiedRecommendation> recommendations = new ArrayList<>();

    // This will be used to find files that have been renamed, but not modified. This is relatively
    // cheap to construct as it just requires indexing all entries by the uncompressed CRC32, and
    // the CRC32 is already available in the ZIP headers.
    SimilarityFinder trivialRenameFinder =
        new Crc32SimilarityFinder(oldFile, oldArchiveZipEntriesByPath.values());

    // Iterate over every pair of entries and get a recommendation for what to do.
    for (Map.Entry<ByteArrayHolder, MinimalZipEntry> newEntry :
        newArchiveZipEntriesByPath.entrySet()) {
      ByteArrayHolder newEntryPath = newEntry.getKey();
      MinimalZipEntry oldZipEntry = oldArchiveZipEntriesByPath.get(newEntryPath);
      if (oldZipEntry == null) {
        // The path is only present in the new archive, not in the old archive. Try to find a
        // similar file in the old archive that can serve as a diff base for the new file.
        List<MinimalZipEntry> identicalEntriesInOldArchive =
            trivialRenameFinder.findSimilarFiles(newFile, newEntry.getValue());
        if (!identicalEntriesInOldArchive.isEmpty()) {
          // An identical file exists in the old archive at a different path. Use it for the
          // recommendation and carry on with the normal logic.
          // All entries in the returned list are identical, so just pick the first one.
          // NB, in principle it would be optimal to select the file that required the least work
          // to apply the patch - in practice, it is unlikely that an archive will contain multiple
          // copies of the same file that are compressed differently, so don't bother with that
          // degenerate case.
          oldZipEntry = identicalEntriesInOldArchive.get(0);
        }
      }

      // If the attempt to find a suitable diff base for the new entry has failed, oldZipEntry is
      // null (nothing to do in that case). Otherwise, there is an old entry that is relevant, so
      // get a recommendation for what to do.
      if (oldZipEntry != null) {
        recommendations.add(getRecommendation(oldZipEntry, newEntry.getValue()));
      }
    }
    return recommendations;
  }
```

这个函数主要做如下工作:

- 创建一个相似文件查找器，内部使用Map进行查找，key为crc32，值为旧文件的MinimalZipEntry，且是一个List，因为crc32相同的文件可能有多个。
- 遍历新文件MinimalZipEntry的List对象，查看对应名字在旧文件中是否存在，如果不存在，则通过第一步的相似文件查找器查找crc32相同的文件，如果找到了，取List对象的第一个。如果找不到，则表示这个文件被移除了，不需要管它。
- 通过旧Entry和新Entry调用getRecommendation函数返回QualifiedRecommendation对象，add到List对象中；该对象持有了新旧Entry，以及新旧文件是否被解压等相关信息。
- 返回找到的QualifiedRecommendation列表

QualifiedRecommendation的生成算法是什么呢，它是调用getRecommendation返回的，该函数代码如下:

```java
 private QualifiedRecommendation getRecommendation(MinimalZipEntry oldEntry, MinimalZipEntry newEntry)
      throws IOException {

    // Reject anything that is unsuitable for uncompressed diffing.
    // Reason singled out in order to monitor unsupported versions of zlib.
    if (unsuitableDeflate(newEntry)) {
      return new QualifiedRecommendation(
          oldEntry,
          newEntry,
          Recommendation.UNCOMPRESS_NEITHER,
          RecommendationReason.DEFLATE_UNSUITABLE);
    }

    // Reject anything that is unsuitable for uncompressed diffing.
    if (unsuitable(oldEntry, newEntry)) {
      return new QualifiedRecommendation(
          oldEntry,
          newEntry,
          Recommendation.UNCOMPRESS_NEITHER,
          RecommendationReason.UNSUITABLE);
    }

    // If both entries are already uncompressed there is nothing to do.
    if (bothEntriesUncompressed(oldEntry, newEntry)) {
      return new QualifiedRecommendation(
          oldEntry,
          newEntry,
          Recommendation.UNCOMPRESS_NEITHER,
          RecommendationReason.BOTH_ENTRIES_UNCOMPRESSED);
    }

    // The following are now true:
    // 1. At least one of the entries is compressed.
    // 1. The old entry is either uncompressed, or is compressed with deflate.
    // 2. The new entry is either uncompressed, or is reproducibly compressed with deflate.

    if (uncompressedChangedToCompressed(oldEntry, newEntry)) {
      return new QualifiedRecommendation(
          oldEntry,
          newEntry,
          Recommendation.UNCOMPRESS_NEW,
          RecommendationReason.UNCOMPRESSED_CHANGED_TO_COMPRESSED);
    }

    if (compressedChangedToUncompressed(oldEntry, newEntry)) {
      return new QualifiedRecommendation(
          oldEntry,
          newEntry,
          Recommendation.UNCOMPRESS_OLD,
          RecommendationReason.COMPRESSED_CHANGED_TO_UNCOMPRESSED);
    }

    // At this point, both entries must be compressed with deflate.
    if (compressedBytesChanged(oldEntry, newEntry)) {
      return new QualifiedRecommendation(
          oldEntry,
          newEntry,
          Recommendation.UNCOMPRESS_BOTH,
          RecommendationReason.COMPRESSED_BYTES_CHANGED);
    }

    // If the compressed bytes have not changed, there is no need to do anything.
    return new QualifiedRecommendation(
        oldEntry,
        newEntry,
        Recommendation.UNCOMPRESS_NEITHER,
        RecommendationReason.COMPRESSED_BYTES_IDENTICAL);
  }
```

主要有7种类型:

- 该文件被压缩过，但是无法推测出其JreDeflateParamyaseters参数，也就是无法获得其压缩级别，编码策略，nowrap三个参数，没有了这三个参数，我们就无法重新进行压缩，因此，对于这种情况，返回的是不建议解压，原因是找不到合适的deflate参数还原压缩数据
- 旧文件，或新文件被压缩了，但是是不支持的压缩算法，则返回不建议解压缩，原因是使用了不支持的压缩算法
- 如果新旧文件都没有被压缩，则返回不需要解压，原因是都没有被压缩
- 如果旧文件未压缩，新文件已压缩，则返回新文件需要解压，原因是从未压缩文件变成了已压缩文件
- 如果旧文件已压缩，新文件未压缩，则返回旧文件需要解压，原因是从已压缩文件变成了未压缩文件
- 如果新旧文件都已经压缩，且发生了变化，则返回需要解压新旧文件，原因是文件发生改变
- 没有新旧文件没有发生变化，则返回不需要解压新旧文件，原因是文件未发生改变



有了以上信息，再来看看差量友好的文件是怎么生成的：

```Java
  private List<TypedRange<JreDeflateParameters>> generateDeltaFriendlyFiles(PreDiffPlan preDiffPlan)
      throws IOException {
    try (FileOutputStream out = new FileOutputStream(deltaFriendlyOldFile);
        BufferedOutputStream bufferedOut = new BufferedOutputStream(out)) {
      DeltaFriendlyFile.generateDeltaFriendlyFile(
          preDiffPlan.getOldFileUncompressionPlan(), originalOldFile, bufferedOut);
    }
    try (FileOutputStream out = new FileOutputStream(deltaFriendlyNewFile);
        BufferedOutputStream bufferedOut = new BufferedOutputStream(out)) {
      return DeltaFriendlyFile.generateDeltaFriendlyFile(
          preDiffPlan.getNewFileUncompressionPlan(), originalNewFile, bufferedOut);
    }
  }

public static <T> List<TypedRange<T>> generateDeltaFriendlyFile(
      List<TypedRange<T>> rangesToUncompress, File file, OutputStream deltaFriendlyOut)
      throws IOException {
    return generateDeltaFriendlyFile(
        rangesToUncompress, file, deltaFriendlyOut, true, DEFAULT_COPY_BUFFER_SIZE);
  }

  public static <T> List<TypedRange<T>> generateDeltaFriendlyFile(
      List<TypedRange<T>> rangesToUncompress,
      File file,
      OutputStream deltaFriendlyOut,
      boolean generateInverse,
      int copyBufferSize)
      throws IOException {
    List<TypedRange<T>> inverseRanges = null;
    if (generateInverse) {
      inverseRanges = new ArrayList<TypedRange<T>>(rangesToUncompress.size());
    }
    long lastReadOffset = 0;
    RandomAccessFileInputStream oldFileRafis = null;
    PartiallyUncompressingPipe filteredOut =
        new PartiallyUncompressingPipe(deltaFriendlyOut, copyBufferSize);
    try {
      oldFileRafis = new RandomAccessFileInputStream(file);
      for (TypedRange<T> rangeToUncompress : rangesToUncompress) {
        long gap = rangeToUncompress.getOffset() - lastReadOffset;
        if (gap > 0) {
          // Copy bytes up to the range start point
          oldFileRafis.setRange(lastReadOffset, gap);
          filteredOut.pipe(oldFileRafis, PartiallyUncompressingPipe.Mode.COPY);
        }

        // Now uncompress the range.
        oldFileRafis.setRange(rangeToUncompress.getOffset(), rangeToUncompress.getLength());
        long inverseRangeStart = filteredOut.getNumBytesWritten();
        // TODO(andrewhayden): Support nowrap=false here? Never encountered in practice.
        // This would involve catching the ZipException, checking if numBytesWritten is still zero,
        // resetting the stream and trying again.
        filteredOut.pipe(oldFileRafis, PartiallyUncompressingPipe.Mode.UNCOMPRESS_NOWRAP);
        lastReadOffset = rangeToUncompress.getOffset() + rangeToUncompress.getLength();

        if (generateInverse) {
          long inverseRangeEnd = filteredOut.getNumBytesWritten();
          long inverseRangeLength = inverseRangeEnd - inverseRangeStart;
          TypedRange<T> inverseRange =
              new TypedRange<T>(
                  inverseRangeStart, inverseRangeLength, rangeToUncompress.getMetadata());
          inverseRanges.add(inverseRange);
        }
      }
      // Finish the final bytes of the file
      long bytesLeft = oldFileRafis.length() - lastReadOffset;
      if (bytesLeft > 0) {
        oldFileRafis.setRange(lastReadOffset, bytesLeft);
        filteredOut.pipe(oldFileRafis, PartiallyUncompressingPipe.Mode.COPY);
      }
    } finally {
      try {
        oldFileRafis.close();
      } catch (Exception ignored) {
        // Nothing
      }
      try {
        filteredOut.close();
      } catch (Exception ignored) {
        // Nothing
      }
    }
    return inverseRanges;
  }
```

这个函数比较巧妙，也比较复杂，其过程如下：

- 遍历需要解压的列表，获得其偏移，将该偏移减去上次读的偏移位置lastReadOffset，得到一个gap值，这个值使用COPY直接拷贝子杰数组
- 然后将数据定位到[offset,offset+length]之间，获得已经解压写入的所有数据大小，赋值给inverseRangeStart，然后将压缩数据使用对应的参数进行解压，将上次读的偏移位置lastReadOffset设置为当前的offset+length值。
- 判断generateInverse是否为true，这里这个值永远为true，因为入参传了true。获得已经解压写入的所有数据大小，赋值给inverseRangeEnd，使用inverseRangeEnd减去inverseRangeStart就是解压之后的大小，构建TypedRange对象，add到list中
- 所有数据遍历完之后，判断当前读的位置到文件结尾是否还有数据剩余，如果有，则继续写入
- 返回TypedRange的List对象。

这个过程比较复杂抽象，用一张图来说明整个文件解压过程。

![friendly_generator.png](friendly_generator.png)

上图是zip文件，绿色的gap是一些描述信息，红色的表示真实的压缩数据，蓝色的表示文件末尾遗留的数据，对于gap，执行拷贝操作，对于压缩数据，执行解压操作，并返回解压之后真实的偏移offset和解压之后真实数据的大小length，所有数据遍历完之后，文件末尾还有一部分遗留数据，对其执行拷贝操作。



特别注意返回的TypedRange是新文件的解压之后的offset和length，这个数据十分重要，还原zip文件就靠这个数据了。



有了新旧文件的差量友好文件之后做什么呢，很简单，使用BsDiff生成差量文件，然后将差量文件写入patch文件。patch文件的格式如下：

| Offset       | Bytes | Description                             | 备注                          |
| ------------ | ----- | --------------------------------------- | --------------------------- |
| 0            | 8     | Versioned Identifier                    | 头部标记，固定值"GFbFv1_0"，UTF-8字符串 |
| 8            | 4     | Flags  (currently unused, but reserved) | 标记未，预留                      |
| 12           | 8     | Delta-friendly old archive size         | 旧文件差量友好文件大小，64位无符号整型        |
| 20           | 4     | Num old archive uncompression ops       | 旧文件待解压文件个数，32位无符号整型         |
| 24           | i     | Old archive uncompression op 1…n        | 旧文件待解压文件的偏移和大小，总共n个         |
| 24+i         | 4     | Num new archive recompression ops       | 新文件待压缩文件个数，32位无符号整型         |
| 24+i+4       | j     | New archive recompression op 1…n        | 新文件待压缩文件的偏移和大小，总共n个         |
| 24+i+4+j     | 4     | Num delta descriptor records            | 新文件差量描述个数，32位无符号整型          |
| 24+i+4+j+4   | k     | Delta descriptor record 1...n           | 差量算法描述记录，总共n个               |
| 24+i+4+j+4+k | l     | Delta 1...n                             | 差量算法描述                      |



Old Archive Uncompression Op的数据结构如下

| Bytes | Description                        | 备注                |
| ----- | ---------------------------------- | ----------------- |
| 8     | Offset of first byte to uncompress | 待解压的偏移位置，64位无符号整型 |
| 8     | Number of bytes to uncompress      | 待解压的字节个数，64位无符号整型 |



New Archive Recompression Op的数据结构如下

| Bytes | Description                      | 备注                     |
| ----- | -------------------------------- | ---------------------- |
| 8     | Offset of first byte to compress | 待压缩的偏移位置，64位无符号整型      |
| 8     | Number of bytes to compress      | 待压缩的字节个数，64位无符号整型      |
| 4     | Compression settings             | 压缩参数，即压缩级别，编码策略，nowrap |

Compression Settings的数据结构如下

| Bytes | Description             | 备注                  |
| ----- | ----------------------- | ------------------- |
| 1     | Compatibility window ID | 兼容窗口，当前取值为0，即默认兼容窗口 |
| 1     | Deflate level           | 压缩级别，取值[1,9]        |
| 1     | Deflate strategy        | 编码策略，取值[0,2]        |
| 1     | Wrap mode               | 取值0=wrap,1=nowrap   |

Compatibility Window即兼容窗口，其默认的兼容窗口ID取值为0，默认兼容窗口使用如下配置

- 使用deflate算法进行压缩（zlib）
- 32768个字节的buffer大小
- 已经被验证的压缩级别，1-9
- 已经被验证过的编码策略，0-2
- 已经被验证过的wrap模式，wrap和nowrap

默认兼容窗口可以兼容Android4.0之后的系统。

这个兼容窗口是怎么得到的呢，其中有一个类叫DefaultDeflateCompatibilityWindow，可以调用getIncompatibleValues获得其不兼容的参数列表JreDeflateParameters（压缩级别，编码策略，nowrap的承载体），内部通过排列组合这三个参数，对一段内容进行压缩，产生压缩后的数据的16进制的编码，与内置的预期数据进行对比，如果相同则表示兼容，不相同表示不兼容。

这里有一个问题，官方表示可以兼容压缩级别1-9，编码策略0-2，wrap和nowrap，但是实际我测试下来，发现在pc上有一部分组合是不兼容的，大概约4个组合。Android上没有测试过，不知道是否有这个问题。

Delta Descriptor Record用于描述差量算法，在当前的V1版Patch中，只有BsDiff算法，因此只有一条该数据结构，其数据结构如下:

| Bytes | Description                      | 备注                    |
| ----- | -------------------------------- | --------------------- |
| 1     | Delta format ID                  | 差量算法对应的枚举id，bsdiff取值0 |
| 8     | Old delta-friendly region start  | 旧文件差量算法应用的偏移位置        |
| 8     | Old delta-friendly region length | 旧文件差量算法应用的长度          |
| 8     | New delta-friendly region start  | 新文件差量算法应用的偏移位置        |
| 8     | New delta-friendly region length | 新文件差量算法应用的长度          |
| 8     | Delta length                     | 生成的差量文件的长度            |

生成patch文件的函数是writeV1Patch，其代码如下：

```java
    public void writeV1Patch(OutputStream out) throws IOException {
    // Use DataOutputStream for ease of writing. This is deliberately left open, as closing it would
    // close the output stream that was passed in and that is not part of the method's documented
    // behavior.
    @SuppressWarnings("resource")
    DataOutputStream dataOut = new DataOutputStream(out);

    dataOut.write(PatchConstants.IDENTIFIER.getBytes("US-ASCII"));//GFbFv1_0
    dataOut.writeInt(0); // Flags (reserved)
    dataOut.writeLong(deltaFriendlyOldFileSize);

    // Write out all the delta-friendly old file uncompression instructions
    dataOut.writeInt(plan.getOldFileUncompressionPlan().size());
    for (TypedRange<Void> range : plan.getOldFileUncompressionPlan()) {
      dataOut.writeLong(range.getOffset());
      dataOut.writeLong(range.getLength());
    }

    // Write out all the delta-friendly new file recompression instructions
    dataOut.writeInt(plan.getDeltaFriendlyNewFileRecompressionPlan().size());
    for (TypedRange<JreDeflateParameters> range : plan.getDeltaFriendlyNewFileRecompressionPlan()) {
      dataOut.writeLong(range.getOffset());
      dataOut.writeLong(range.getLength());
      // Write the deflate information
      dataOut.write(PatchConstants.CompatibilityWindowId.DEFAULT_DEFLATE.patchValue);
      dataOut.write(range.getMetadata().level);
      dataOut.write(range.getMetadata().strategy);
      dataOut.write(range.getMetadata().nowrap ? 1 : 0);
    }

    // Now the delta section
    // First write the number of deltas present in the patch. In v1, there is always exactly one
    // delta, and it is for the entire input; in future versions there may be multiple deltas, of
    // arbitrary types.
    dataOut.writeInt(1);
    // In v1 the delta format is always bsdiff, so write it unconditionally.
    dataOut.write(PatchConstants.DeltaFormat.BSDIFF.patchValue);

    // Write the working ranges. In v1 these are always the entire contents of the delta-friendly
    // old file and the delta-friendly new file. These are for forward compatibility with future
    // versions that may allow deltas of arbitrary formats to be mapped to arbitrary ranges.
    dataOut.writeLong(0); // i.e., start of the working range in the delta-friendly old file
    dataOut.writeLong(deltaFriendlyOldFileSize); // i.e., length of the working range in old
    dataOut.writeLong(0); // i.e., start of the working range in the delta-friendly new file
    dataOut.writeLong(deltaFriendlyNewFileSize); // i.e., length of the working range in new

    // Finally, the length of the delta and the delta itself.
    dataOut.writeLong(deltaFile.length());
    try (FileInputStream deltaFileIn = new FileInputStream(deltaFile);
        BufferedInputStream deltaIn = new BufferedInputStream(deltaFileIn)) {
      byte[] buffer = new byte[32768];
      int numRead = 0;
      while ((numRead = deltaIn.read(buffer)) >= 0) {
        dataOut.write(buffer, 0, numRead);
      }
    }
    dataOut.flush();
  }
```

主要做了如下几步：

- 写入文件头，"GFbFv1_0"
- 写入标记位，预留，值为0
- 写入旧文件差量友好文件的大小
- 写入旧文件需要解压的entry个数
- 依次写入旧文件n个待解压的entry的偏移和长度
- 写入新文件需要压缩的entry的个数
- 依次写入新文件n个待压缩的entry的偏移和长度，兼容窗口（窗口id，压缩级别，压缩策略，nowrap）
- 写入差量算法描述个数，只使用了bsdiff，因此值为1
- 写入差量算法id，旧文件差量友好文件应用差量算法的偏移和长度，新文件差量友好文件应用差量算法的偏移和长度
- 写入patch文件的大小
- 写入bsdiff生成的patch文件内容



### 新文件的合成

合成主要通过com.google.archivepatcher.applier.FileByFileV1DeltaApplier的applyDelta，最终会调用到applyDeltaInternal方法，其代码如下：

```Java
private void applyDeltaInternal(
      File oldBlob, File deltaFriendlyOldBlob, InputStream deltaIn, OutputStream newBlobOut)
      throws IOException {

    // First, read the patch plan from the patch stream.
    PatchReader patchReader = new PatchReader();
    PatchApplyPlan plan = patchReader.readPatchApplyPlan(deltaIn);
    writeDeltaFriendlyOldBlob(plan, oldBlob, deltaFriendlyOldBlob);
    // Apply the delta. In v1 there is always exactly one delta descriptor, it is bsdiff, and it
    // takes up the rest of the patch stream - so there is no need to examine the list of
    // DeltaDescriptors in the patch at all.
    long deltaLength = plan.getDeltaDescriptors().get(0).getDeltaLength();
    DeltaApplier deltaApplier = getDeltaApplier();
    // Don't close this stream, as it is just a limiting wrapper.
    @SuppressWarnings("resource")
    LimitedInputStream limitedDeltaIn = new LimitedInputStream(deltaIn, deltaLength);
    // Don't close this stream, as it would close the underlying OutputStream (that we don't own).
    @SuppressWarnings("resource")
    PartiallyCompressingOutputStream recompressingNewBlobOut =
        new PartiallyCompressingOutputStream(
            plan.getDeltaFriendlyNewFileRecompressionPlan(),
            newBlobOut,
            DEFAULT_COPY_BUFFER_SIZE);
    deltaApplier.applyDelta(deltaFriendlyOldBlob, limitedDeltaIn, recompressingNewBlobOut);
    recompressingNewBlobOut.flush();
  }
```

主要做了如下几件事：

- 解析patch文件生成PatchApplyPlan对象
- 生成旧文件的差量友好文件
- 应用合成算法，合成新文件的差量友好文件，于此同时新文件zip包在流的写入过程中完成合成。

对于第一步，来看看如何解析的，解析代码如下:

```Java
 public PatchApplyPlan readPatchApplyPlan(InputStream in) throws IOException {
    // Use DataOutputStream for ease of writing. This is deliberately left open, as closing it would
    // close the output stream that was passed in and that is not part of the method's documented
    // behavior.
    @SuppressWarnings("resource")
    DataInputStream dataIn = new DataInputStream(in);

    // Read header and flags.
    byte[] expectedIdentifier = PatchConstants.IDENTIFIER.getBytes("US-ASCII");
    byte[] actualIdentifier = new byte[expectedIdentifier.length];
    dataIn.readFully(actualIdentifier);
    if (!Arrays.equals(expectedIdentifier, actualIdentifier)) {
      throw new PatchFormatException("Bad identifier");
    }
    dataIn.skip(4); // Flags (ignored in v1)
    long deltaFriendlyOldFileSize = checkNonNegative(
        dataIn.readLong(), "delta-friendly old file size");

    // Read old file uncompression instructions.
    int numOldFileUncompressionInstructions = (int) checkNonNegative(
        dataIn.readInt(), "old file uncompression instruction count");
    List<TypedRange<Void>> oldFileUncompressionPlan =
        new ArrayList<TypedRange<Void>>(numOldFileUncompressionInstructions);
    long lastReadOffset = -1;
    for (int x = 0; x < numOldFileUncompressionInstructions; x++) {
      long offset = checkNonNegative(dataIn.readLong(), "old file uncompression range offset");
      long length = checkNonNegative(dataIn.readLong(), "old file uncompression range length");
      if (offset < lastReadOffset) {
        throw new PatchFormatException("old file uncompression ranges out of order or overlapping");
      }
      TypedRange<Void> range = new TypedRange<Void>(offset, length, null);
      oldFileUncompressionPlan.add(range);
      lastReadOffset = offset + length; // To check that the next range starts after the current one
    }

    // Read new file recompression instructions
    int numDeltaFriendlyNewFileRecompressionInstructions = dataIn.readInt();
    checkNonNegative(
        numDeltaFriendlyNewFileRecompressionInstructions,
        "delta-friendly new file recompression instruction count");
    List<TypedRange<JreDeflateParameters>> deltaFriendlyNewFileRecompressionPlan =
        new ArrayList<TypedRange<JreDeflateParameters>>(
            numDeltaFriendlyNewFileRecompressionInstructions);
    lastReadOffset = -1;
    for (int x = 0; x < numDeltaFriendlyNewFileRecompressionInstructions; x++) {
      long offset = checkNonNegative(
          dataIn.readLong(), "delta-friendly new file recompression range offset");
      long length = checkNonNegative(
          dataIn.readLong(), "delta-friendly new file recompression range length");
      if (offset < lastReadOffset) {
        throw new PatchFormatException(
            "delta-friendly new file recompression ranges out of order or overlapping");
      }
      lastReadOffset = offset + length; // To check that the next range starts after the current one

      // Read the JreDeflateParameters
      // Note that v1 only supports the default deflate compatibility window.
      checkRange(
          dataIn.readByte(),
          PatchConstants.CompatibilityWindowId.DEFAULT_DEFLATE.patchValue,
          PatchConstants.CompatibilityWindowId.DEFAULT_DEFLATE.patchValue,
          "compatibility window id");
      int level = (int) checkRange(dataIn.readUnsignedByte(), 1, 9, "recompression level");
      int strategy = (int) checkRange(dataIn.readUnsignedByte(), 0, 2, "recompression strategy");
      int nowrapInt = (int) checkRange(dataIn.readUnsignedByte(), 0, 1, "recompression nowrap");
      TypedRange<JreDeflateParameters> range =
          new TypedRange<JreDeflateParameters>(
              offset,
              length,
              JreDeflateParameters.of(level, strategy, nowrapInt == 0 ? false : true));
      deltaFriendlyNewFileRecompressionPlan.add(range);
    }

    // Read the delta metadata, but stop before the first byte of the actual delta.
    // V1 has exactly one delta and it must be bsdiff.
    int numDeltaRecords = (int) checkRange(dataIn.readInt(), 1, 1, "num delta records");

    List<DeltaDescriptor> deltaDescriptors = new ArrayList<DeltaDescriptor>(numDeltaRecords);
    for (int x = 0; x < numDeltaRecords; x++) {
      byte deltaFormatByte = (byte)
      checkRange(
          dataIn.readByte(),
          PatchConstants.DeltaFormat.BSDIFF.patchValue,
          PatchConstants.DeltaFormat.BSDIFF.patchValue,
          "delta format");
      long deltaFriendlyOldFileWorkRangeOffset = checkNonNegative(
          dataIn.readLong(), "delta-friendly old file work range offset");
      long deltaFriendlyOldFileWorkRangeLength = checkNonNegative(
          dataIn.readLong(), "delta-friendly old file work range length");
      long deltaFriendlyNewFileWorkRangeOffset = checkNonNegative(
          dataIn.readLong(), "delta-friendly new file work range offset");
      long deltaFriendlyNewFileWorkRangeLength = checkNonNegative(
          dataIn.readLong(), "delta-friendly new file work range length");
      long deltaLength = checkNonNegative(dataIn.readLong(), "delta length");
      DeltaDescriptor descriptor =
          new DeltaDescriptor(
              PatchConstants.DeltaFormat.fromPatchValue(deltaFormatByte),
              new TypedRange<Void>(
                  deltaFriendlyOldFileWorkRangeOffset, deltaFriendlyOldFileWorkRangeLength, null),
              new TypedRange<Void>(
                  deltaFriendlyNewFileWorkRangeOffset, deltaFriendlyNewFileWorkRangeLength, null),
              deltaLength);
      deltaDescriptors.add(descriptor);
    }

    return new PatchApplyPlan(
        Collections.unmodifiableList(oldFileUncompressionPlan),
        deltaFriendlyOldFileSize,
        Collections.unmodifiableList(deltaFriendlyNewFileRecompressionPlan),
        Collections.unmodifiableList(deltaDescriptors));
  }
```

分为以下几个步骤：

- 读文件头，校验文件头
- 忽略4个字节的标记位
- 读旧文件差量友好文件的大小，并校验，非负数
- 读旧文件待解压的个数，并校验，非负数
- 读n个旧文件待解压的偏移，长度，并校验，非负数
- 读新文件待压缩的个数，并校验，非负数
- 读n个新文件待压缩的偏移，长度，并校验，非负数，压缩级别，编码策略，nowrap值
- 读差量算法个数
- 读n个差量算法描述。差量算法id，旧文件应用差量算法的偏移和长度，新文件应用差量算法的偏移和长度，生成的差量文件的大小
- 返回PatchApplyPlan对象

接下来就是根据返回的PatchApplyPlan对象，获得旧文件待解压的一个TypedRange的List对象，然后使用DeltaFriendlyFile.generateDeltaFriendlyFile生产差量友好文件，这个过程和生产patch的那个过程一样，不重复描述。其代码如下：

```java
 private void writeDeltaFriendlyOldBlob(
      PatchApplyPlan plan, File oldBlob, File deltaFriendlyOldBlob) throws IOException {
    RandomAccessFileOutputStream deltaFriendlyOldFileOut = null;
    try {
      deltaFriendlyOldFileOut =
          new RandomAccessFileOutputStream(
              deltaFriendlyOldBlob, plan.getDeltaFriendlyOldFileSize());
      DeltaFriendlyFile.generateDeltaFriendlyFile(
          plan.getOldFileUncompressionPlan(),
          oldBlob,
          deltaFriendlyOldFileOut,
          false,
          DEFAULT_COPY_BUFFER_SIZE);
    } finally {
      try {
        deltaFriendlyOldFileOut.close();
      } catch (Exception ignored) {
        // Nothing
      }
    }
```

接下里就是合成新文件了，使用BsPatch算法完成合成并写入Outputstream中，而这个OutputStream经过装饰者模式包装，最终传入的是PartiallyCompressingOutputStream输出流，构建PartiallyCompressingOutputStream对象所需参数就是新文件差量友好文件需要重新压缩的数据的TypedRange的List对象。最终，合成Zip文件的工作会辗转到PartiallyCompressingOutputStream中的writeChunk函数，其代码如下：

```Java
private int writeChunk(byte[] buffer, int offset, int length) throws IOException {
    if (bytesTillCompressionStarts() == 0 && !currentlyCompressing()) {
      // Compression will begin immediately.
      JreDeflateParameters parameters = nextCompressedRange.getMetadata();
      if (deflater == null) {
        deflater = new Deflater(parameters.level, parameters.nowrap);
      } else if (lastDeflateParameters.nowrap != parameters.nowrap) {
        // Last deflater must be destroyed because nowrap settings do not match.
        deflater.end();
        deflater = new Deflater(parameters.level, parameters.nowrap);
      }
      // Deflater will already have been reset at the end of this method, no need to do it again.
      // Just set up the right parameters.
      deflater.setLevel(parameters.level);
      deflater.setStrategy(parameters.strategy);
      deflaterOut = new DeflaterOutputStream(normalOut, deflater, compressionBufferSize);
    }

    int numBytesToWrite;
    OutputStream writeTarget;
    if (currentlyCompressing()) {
      // Don't write past the end of the compressed range.
      numBytesToWrite = (int) Math.min(length, bytesTillCompressionEnds());
      writeTarget = deflaterOut;
    } else {
      writeTarget = normalOut;
      if (nextCompressedRange == null) {
        // All compression ranges have been consumed.
        numBytesToWrite = length;
      } else {
        // Don't write past the point where the next compressed range begins.
        numBytesToWrite = (int) Math.min(length, bytesTillCompressionStarts());
      }
    }

    writeTarget.write(buffer, offset, numBytesToWrite);
    numBytesWritten += numBytesToWrite;

    if (currentlyCompressing() && bytesTillCompressionEnds() == 0) {
      // Compression range complete. Finish the output and set up for the next run.
      deflaterOut.finish();
      deflaterOut.flush();
      deflaterOut = null;
      deflater.reset();
      lastDeflateParameters = nextCompressedRange.getMetadata();
      if (rangeIterator.hasNext()) {
        // More compression ranges await in the future.
        nextCompressedRange = rangeIterator.next();
      } else {
        // All compression ranges have been consumed.
        nextCompressedRange = null;
        deflater.end();
        deflater = null;
      }
    }

    return numBytesToWrite;
  }

  private boolean currentlyCompressing() {
    return deflaterOut != null;
  }

  private long bytesTillCompressionStarts() {
    if (nextCompressedRange == null) {
      // All compression ranges have been consumed
      return -1L;
    }
    return nextCompressedRange.getOffset() - numBytesWritten;
  }

  private long bytesTillCompressionEnds() {
    if (nextCompressedRange == null) {
      // All compression ranges have been consumed
      return -1L;
    }
    return (nextCompressedRange.getOffset() + nextCompressedRange.getLength()) - numBytesWritten;
  }
```

合成算法的核心就是这个函数了，这个函数设计的十分巧妙，建议打个断点跑一跑，好好理解一下。这里简单介绍一下这个过程。

- 在PartiallyCompressingOutputStream的构造函数中，获得了compressionRanges的第一个数据
- 判断写入的数据距离下一个压缩数据开始如果是0，且当前并不在压缩，则获得压缩设置，即压缩级别，编码策略，nowrap，并进行设置。并包装输出流为压缩流。
- 如果当前正在压缩，则判断当前写入的数据长度和待压缩的数据长度，取其中小的一个，设置目标输出流为压缩流，即负责压缩工作，而不是拷贝工作。
- 如果当前不在压缩，如果没有下一个压缩数据了，则直接写入对应长度的数据，如果还有下一个压缩数据，则取当前写入数据的长度和距离下一个压缩数据的偏移位置的长度，取其中小的一个，设置目标输出流为正常流，即进行拷贝工作，而不是压缩工作
- 判断当前是否正在压缩，并且当前节点所有压缩数据都已经写入完全，执行压缩流的finish和flush操作，重置压缩相关配置项，并移动待压缩的数据到下一条记录。
- 重复以上操作，直到所有数据写入完全。

过程比较复杂，同样的用一张图来表示:

![recompress.png](recompress.png)

合成的新的差量友好的文件数据如上图表示。

当遇到绿色的gap区域时，则执行二进制拷贝操作，将其拷贝到输出流去，当遇到红色的已经解压的数据，会使用对应的压缩级别，编码策略，nowrap参数将数据进行压缩，将蓝色的剩余数据写入目标数据。

就这样整个合成操作就完成了。

这样为何能完成zip文件的合成呢，上面的解析已经很清楚了，其实Google Archive Patch记录了所有新文件中需要重新压缩的数据的参数，对于这些数据，使用这些参数压缩，得到对应的压缩数据，写入其在新文件的真实位置，而对于Zip文件中的其他数据，则执行的是拷贝操作，这样两种操作合起来，最终就产生了新的Zip文件。且对于Apk来说，我们也无需关心其签名。

这个过程真是巧妙，感叹一下 !

### Patch文件的压缩和解压

Google Archive Patch不对patch文件进行压缩，压缩工作需要自己进行，保证patch文件的大小很小，而客户端接受到patch后需要对应的解压。这么做，保证了压缩patch算法的充分自由，可自行选择，方便扩展。

### 通用的差量生成和合成框架

这几天简单的实现了一个通用的差量生成和合成框架，github地址见 [CorePatch](https://github.com/lizhangqu/CorePatch) ,目前已经实现bsdiff和Google Archive Patch以及全量合成（直接拷贝文件）

### 优化

#### 生成差量文件优化

生成差量文件使用的是bsdiff，但是对应的基础文件经过解压之后，其文件大小大大变大，导致生成差量文件的时间大大增加，这里没有办法优化，唯一的优化点就是使用其他更优差量生成算法，而不是BsDiff算法。

#### 合成新文件优化

合成使用BsPatch进行合成，这个过程是十分快的，因此这里可以不优化，但是需要优化的点是合成新的Zip文件过程，即上面提到的writeChunk函数，而这个函数，唯一的耗时点就是压缩操作，基本上压缩操作耗时占全部耗时的80%-90%左右，所以这里基本没什么优化点。

### 总结

Google Archive Patch的核心是生成差量友好文件，应用差量算法，记录新文件差量友好文件中需要重新压缩的偏移和长度，应用合成算法合成新文件时，对于需要重新压缩的数据，用patch中的压缩相关的参数进行压缩，得到压缩数据，而对于非压缩数据，如Zip文件格式中其他数据，则执行拷贝操作。最终完美的合成了新文件，这种方式的优点是patch比基于文件级别的bsdiff生成的要小，缺点是生成时间长，合成时间长。

该算法核心的一个基本要求就是使用相同的压缩级别，编码策略和nowrap参数，对相同的数据进行压缩，得到的数据数据。如果这个前提如果不满足，则该算法就没有意义了。
