title: Flutter 动态化探索
date: 2019-03-22 09:23:50
categories: [Flutter]
tags: [flutter, patch, dynamic]
---

### 前言

Flutter 从某个版本开始，官方就已经支持了Android的动态下发，iOS由于苹果的限制，目前没有特别好的实现方式。现在master分支上最新的代码已经支持Android动态下发了，本篇文章基于v1.3.13。关于动态下发的相关代码可以见如下几个类：
 - [ResourceUpdater.java](https://github.com/flutter/engine/blob/master/shell/platform/android/io/flutter/view/ResourceUpdater.java)
 - [ResourceExtractor.java](https://github.com/flutter/engine/blob/master/shell/platform/android/io/flutter/view/ResourceExtractor.java)
 - [FlutterMain.java](https://github.com/flutter/engine/blob/master/shell/platform/android/io/flutter/view/FlutterMain.java)

<!-- more -->

### 官方方案现状

官方的动态下发其整体的思路就是替换Flutter的产物文件，并且与bsdiff进行结合减小产物的大小。

但是目前官方实现的这种方式过于鸡肋，基本不能直接拿来用，比如：

 - url下载的格式固定，无法与现有的灰度系统进行结合。
 - 自定义能力基本为零，不能干预patch的下载流程，安装流程等等。
 - 如果有patch的话，每次启动都会去下载patch文件，导致重复下载，浪费数据流量。
 - 只能基于dynamicRelease的buildType进行构建，且只能使用flutter命令构建，无法使用gradle进行构建。
 - 对混合应用的patch构建支持基本为零。
 - 只能支持Flutter相关产物，对于原生的产物不允许发生变化，如classes.dex等。这是必然的，除非加以改正，否则必然只能支持Flutter的产物。
 - 缺乏patch签名校验，带来安全问题。

所以官方必须修改其方案，至少要以接口的形式暴露一些自定义的流程，如patch的url获取，patch的下载，patch文件的校验流程，patch的安装流程，可以适当进行扩展。否则现有的方案基本不可能直接进行使用。

### 官方方案更新流程

在我们调用 FlutterMain.startInitialization(context) 的时候，会去判断我们是否支持动态下发。

```
Bundle metaData = null;
try {
    metaData = context.getPackageManager().getApplicationInfo(
            context.getPackageName(), PackageManager.GET_META_DATA).metaData;

} catch (PackageManager.NameNotFoundException e) {
    Log.e(TAG, "Unable to read application info", e);
}

if (metaData != null && metaData.getBoolean("DynamicPatching")) {
    sResourceUpdater = new ResourceUpdater(context);
    // Also checking for ON_RESUME here since it's more efficient than waiting for actual
    // onResume. Even though actual onResume is imminent when the app has just restarted,
    // it's better to start downloading now, in parallel with the rest of initialization,
    // and avoid a second application restart a bit later when actual onResume happens.
    if (sResourceUpdater.getDownloadMode() == ResourceUpdater.DownloadMode.ON_RESTART ||
        sResourceUpdater.getDownloadMode() == ResourceUpdater.DownloadMode.ON_RESUME) {
        sResourceUpdater.startUpdateDownloadOnce();
        if (sResourceUpdater.getInstallMode() == ResourceUpdater.InstallMode.IMMEDIATE) {
            sResourceUpdater.waitForDownloadCompletion();
        }
    }
}
```

它会从AndroidManifest.xml中读取metaData键为DynamicPatching的值，如果为true，就会新建一个ResourceUpdater对象，负责patch的下载，校验等等，后续只要该对象不为null，都会进入动态下发的流程，否则走apk释放流程。

如果下载模式是ON_RESTART或者ON_RESUME，就会执行下载。

这里需要注意如果下载模式是ON_RESUME时，则执行onResume回调时，也会执行下载。

```
public static void onResume(Context context) {
    if (sResourceUpdater != null) {
        if (sResourceUpdater.getDownloadMode() == ResourceUpdater.DownloadMode.ON_RESUME) {
            sResourceUpdater.startUpdateDownloadOnce();
        }
    }
}
```

这里还有一个问题，就是无论patch是否下载成功了，每次执行startUpdateDownloadOnce的时候，都会重新去下载一遍，也就是说下载模式是ON_RESTART的时候，每次冷启动都会去下载一次patch，下载模式是ON_RESUME的时候，每次冷启动以及onResume回调的时候，都会去下载一次patch。这里至少要做一个文件重复的判断，如果要下载的文件md5与本地以及存在的文件md5一致，则不去重复下载。

此时如果安装模式是立即安装的话，即IMMEDIATE模式，则会阻塞等待下载完成，否则下次重新启动的时候安装。

也就是说要想使用官方的这种方式，首先需要在AndroidManifest.xml中声明 DynamicPatching=true

```
<application>
    <meta-data
        android:name="DynamicPatching"
        android:value="true" />
</application>
```

其中下载模式和安装模式也是静态声明在AndroidManifest.xml中，如果不声明，默认的安装模式为ON_NEXT_RESTART，即下次安装，默认的下载模式为ON_RESTART，即下次重启下载。对应在AndroidManifest.xml中的键名为PatchDownloadMode和PatchInstallMode，这也直接导致了无法动态变更某个patch的下载模式和安装模式，因为它是静态写死在AndroidManifest.xml文件中的。

这里需要明确一个问题，我们为什么希望能根据单个patch改变下载和安装模式呢？因为下发patch意味着bug，而有些致命的bug我们希望能及时得到更新，也就是立即安装，相当于启动的时候阻塞去下载安装，而对于一些一般的的问题，可能没那么紧急，只需要下次重启安装即可。

而下载的url则更是奇葩，内部写死url拼接规则，请问哪个公司的下载url是按照这个格式的？这就直接导致了无法与现有灰度系统和cdn进行结合使用。

```
private String buildUpdateDownloadURL() {
    Bundle metaData;
    try {
        metaData = context.getPackageManager().getApplicationInfo(
                context.getPackageName(), PackageManager.GET_META_DATA).metaData;

    } catch (PackageManager.NameNotFoundException e) {
        throw new RuntimeException(e);
    }

    if (metaData == null || metaData.getString("PatchServerURL") == null) {
        return null;
    }

    URI uri;
    try {
        uri = new URI(metaData.getString("PatchServerURL") + "/" + getAPKVersion() + ".zip");

    } catch (URISyntaxException e) {
        Log.w(TAG, "Invalid AndroidManifest.xml PatchServerURL: " + e.getMessage());
        return null;
    }

    return uri.normalize().toString();
}
```

从代码中可以看出，下载的url前缀来自AndroidManifest.xml中键为PatchServerURL的metaData，最终的url为 PatchServerURL后面拼接versionCode.zip即为最终的下载url。这个操作可谓骚得无法拯救，简直智障。

具体的详细流程有兴趣可以查看代码，这里简要概括一下主流程。

 - 初始化的时候判断是否配置了DynamicPatching=true，如果为true，则进入动态更新执行流程
 - 执行patch的下载操作，其url为 PatchServerURL + "/" + versionCode.zip，下载的临时文件为patch.zip.download，下载完成后，重命名为patch.zip.install
 - 校验patch.zip.install文件中manifest.json中相关值，主要为buildNumber是否匹配，基线crc32校验是否匹配，其中crc32主要计算 isolate_snapshot_data, isolate_snapshot_instr, flutter_assets/isolate_snapshot_data 这三个文件，校验成功后，将patch.zip.install文件重名为patch.zip文件。
 - 校验时间戳，此时的时间戳如果patch.zip文件存在，则会把patchNumber和patch.zip文件最后修改的时间一起加入进行计算，其整体格式为 res_timestamp-\$versionCode-\$lastInstallTime-\$patchNumber-\$patchFile.lastModifiedTime，如果过期了，则会进入patch重新释放的流程
 - 如果patch.zip文件存在，则进入释放流程，释放的时候就按文件释放，如果文件名以.bzdiff40结尾，则先执行bspatch合成文件再释放，否则直接释放。此时patch.zip中只会包含改变的文件，对于没有改变的文件则从apk中进行释放。
 - 从安装的apk文件中释放剩余文件，如果已经存在，则不释放。
 - 重新创建最新的时间戳文件，表示最新文件释放成功。
 - 进入so加载流程，如果释放的产物中包含so，则从释放的产物中进行加载，否则从apk安装时是否的so进行加载。

总的来看，如果要复用官方的这套流程，我们至少需要解决以下几个问题
 - patch下载的url可自定义
 - patch的下载模式和安装模式可根据patch文件的粒度动态变化
 - patch防重复下载机制，节约用户流量
 - patch签名校验机制，保障安全性

### 官方方案patch构建

以上是客户端的patch安装流程，那么官方的方案如何构建patch呢？

在构建patch前，我们必须先产生一个基线文件。值得注意的是，官方的方案，只能基于dynamicRelease的buildType进行构建，所以我们必须在app中加入该buildType

```
buildTypes {
    dynamicRelease{
        initWith release
    }
}
```

构建基线文件

```
flutter build apk --release --dynamic
```

将构建产生的apk文件复制出来，假如此时的apk的versionCode为1，则我们将其拷贝到flutter工程目录下的与.android同级目录的.baseline/1.apk，如图所示

![baseline.png](baseline.png)

修改flutter的代码，然后执行patch的构建，此时只能修改flutter代码，不能修改嵌入层的代码，如Java，并且会基于.baseline/\$versonCode.apk为基线文件，当然也可以通过参数传入基线文件，但是为了方便，这里我们直接使用默认的路径规则，修改完成后，执行如下命令构建

```
flutter build apk --release --dynamic --patch
```

看到如下输出，就表示构建成功了，构建成功的patch位于flutter工程目录下public/\$versionCode.zip

![build_patch.png](build_patch.png)

产生的patch文件大致如下所示，包含了manifest.json文件，里面含有buildNumber，patchNumber，以及基线相关文件的crc32值，还有对应的改变的文件，如果是某些特定的文件，会使用bsdiff算法进行差量，产生.bzdiff40文件。

![patch_file.png](patch_file.png)

这里需要思考两个问题
 - 我们能否直接使用gradle命令构建出patch文件？
 - 原生与Flutter混合开发的应用能否构建出patch文件？

对于以上两个问题，答案都是否定的（当然也有可能是我没有找到正确的方式）。为什么呢？

对于第一个问题，为什么不能使用gradle命令直接构建出patch文件呢？因为flutter的patch文件是基于apk进行产生的，其生成的patch的代码逻辑位于 /path/to/flutter/packages/flutter_tools/lib/src/android/gradle.dart，该文件的执行入口正是必须使用flutter命令才会进入，直接使用gradle命令走的是另一个分支的代码，并不会进入生成patch文件的流程。gradle.dart生成patch的代码逻辑大致如下

```
final AndroidApk package = AndroidApk.fromApk(apkFile);
final Directory baselineDir = fs.directory(buildInfo.baselineDir);
final File baselineApkFile = baselineDir.childFile('${package.versionCode}.apk');
if (!baselineApkFile.existsSync())
  throwToolExit('Error: Could not find baseline package ${baselineApkFile.path}.');

printStatus('Found baseline package ${baselineApkFile.path}.');
printStatus('Creating dynamic patch...');
final Archive newApk = ZipDecoder().decodeBytes(apkFile.readAsBytesSync());
final Archive oldApk = ZipDecoder().decodeBytes(baselineApkFile.readAsBytesSync());

final Archive update = Archive();
for (ArchiveFile newFile in newApk) {
  if (!newFile.isFile)
    continue;

  // Ignore changes to signature manifests.
  if (newFile.name.startsWith('META-INF/'))
    continue;

  final ArchiveFile oldFile = oldApk.findFile(newFile.name);
  if (oldFile != null && oldFile.crc32 == newFile.crc32)
    continue;

  // Only allow certain changes.
  if (!newFile.name.startsWith('assets/') &&
      !(buildInfo.usesAot && newFile.name.endsWith('.so')))
    throwToolExit("Error: Dynamic patching doesn't support changes to ${newFile.name}.");

  final String name = newFile.name;
  if (name.contains('_snapshot_') || name.endsWith('.so')) {
    final List<int> diff = bsdiff(oldFile.content, newFile.content);
    final int ratio = 100 * diff.length ~/ newFile.content.length;
    printStatus('Deflated $name by ${ratio == 0 ? 99 : 100 - ratio}%');
    update.addFile(ArchiveFile(name + '.bzdiff40', diff.length, diff));
  } else {
    update.addFile(ArchiveFile(name, newFile.content.length, newFile.content));
  }
}

File updateFile;
if (buildInfo.patchNumber != null) {
  updateFile = fs.directory(buildInfo.patchDir)
      .childFile('${package.versionCode}-${buildInfo.patchNumber}.zip');
} else {
  updateFile = fs.directory(buildInfo.patchDir)
      .childFile('${package.versionCode}.zip');
}

if (update.files.isEmpty) {
  printStatus('No changes detected, creating rollback patch.');
}

final List<String> checksumFiles = <String>[
  'assets/isolate_snapshot_data',
  'assets/isolate_snapshot_instr',
  'assets/flutter_assets/isolate_snapshot_data',
];

int baselineChecksum = 0;
for (String fn in checksumFiles) {
  final ArchiveFile oldFile = oldApk.findFile(fn);
  if (oldFile != null)
    baselineChecksum = getCrc32(oldFile.content, baselineChecksum);
}
if (baselineChecksum == 0)
  throwToolExit('Error: Could not find baseline VM snapshot.');

final Map<String, dynamic> manifest = <String, dynamic>{
  'baselineChecksum': baselineChecksum,
  'buildNumber': package.versionCode,
};

if (buildInfo.patchNumber != null) {
  manifest.addAll(<String, dynamic>{
    'patchNumber': buildInfo.patchNumber,
  });
}

const JsonEncoder encoder = JsonEncoder.withIndent('  ');
final String manifestJson = encoder.convert(manifest);
update.addFile(ArchiveFile('manifest.json', manifestJson.length, manifestJson.codeUnits));

updateFile.parent.createSync(recursive: true);
updateFile.writeAsBytesSync(ZipEncoder().encode(update), flush: true);
final String patchSize = getSizeAsMB(updateFile.lengthSync());
printStatus('Created dynamic patch ${updateFile.path} ($patchSize).');
```

具体流程其实很简单，就是比较特定文件，将改变的文件打入patch包，部分特殊文件使用bsdiff进行差量减小包大小，最后生成manifest.json文件，产生patch包。

从以上流程我们也可以看出，整个patch包虽然有crc32的基线校验，但是并没有对patch包进行签名，所以这里存在一个风险点，容易被不法分子利用。

对于第二个问题 原生与Flutter混合开发的应用能否构建出patch文件，其实这个问题的答案是基于第一个问题的，混合开发的应用，一般打包不会直接基于flutter命令打包，而是先基于flutter命令打包出相关flutter产物，然后和涉及到的Android代码一起打包成aar文件，发布到远程maven仓库，然后在原生应用侧通过gradle远程依赖进行构建。

所以问题很明确，最终混合开发的应用打包肯定是基于gradle命令，而非flutter命令，但是由于目前patch只能基于flutter命令构建，所以混合开发的应用目前无法构建patch。

这两个问题也就变成了我们需要解决的问题，即需要提供一套流程，使用gradle命令进行打包，从而支持混合开发的应用。

### 给Flutter打Call

#### 基于Gradle的patch构建

从Dart代码可以看出，flutter的patch文件构建其实很简单，只要对比差异文件，特定文件生成bsdiff差分文件，根据基线包生成manifest.json文件，打包成zip文件即可，因此基于gradle的patch构建其实变得很简单，我们只要仿造dart代码，基于gradle实现一套patch构建流程即可，只要输入基线apk和新的apk，就能产生一个patch文件，这正是我们想要达到的，不需要强依赖于Flutter环境。

Flutter的patch有部分文件是基于bsdiff的，这部分代码我们可以直接复用tencent的tinker中的BSDiff类，见 [BSDiff.java](https://github.com/Tencent/tinker/blob/master/third-party/bsdiff-util/src/main/java/com/tencent/tinker/bsdiff/BSDiff.java)

但是需要注意的是，bsdiff control block中几个字段的数据结构长度问题，查看了一些实现，有些地方这几个字段占用4个字节，有些地方这几个字段占用8个字节，而tinker中的实现这几个字段占用的是4个字节，但是Flutter中的实现，这几个字段占用的是8个字节，所以如果直接把Tinker中的类拿来使用的话，会导致合成的文件的时候文件非法，我们需要做两个修改。

第一个是Magic Bytes的修改，将其从MicroMsg修改为BZDIFF40，代码如下

```
private static final byte[] MAGIC_BYTES = "BZDIFF40".getBytes();
```

第二个就是将上面说到的几个字段从4字节修改为8字节，找到如下代码

```
// Write control block entry (3 x int)
dataOut.writeInt(lenFromOld);  // oldBuf
dataOut.writeInt((scan - lenb) - (lastscan + lenFromOld));  // diffBufextraBlock
dataOut.writeInt((pos.value - lenb) - (lastpos + lenFromOld));  // oldBuf
```

将其修改为

```
// Write control block entry (3 x int)
dataOut.writeLong(lenFromOld);  // oldBuf
dataOut.writeLong((scan - lenb) - (lastscan + lenFromOld));  // diffBufextraBlock
dataOut.writeLong((pos.value - lenb) - (lastpos + lenFromOld));  // oldBuf
```

修改完成后就可以直接使用了。

后面我们只需要仿造Dart代码，用groovy重写一下即可，具体代码大致如下：

```
newApk.entries().each { ZipEntry newFile ->
    if (newFile.isDirectory()) {
        return
    }
    // Ignore changes to signature manifests.
    if (newFile.getName().startsWith('META-INF/')) {
        return
    }

    ZipEntry oldFile = oldApk.getEntry(newFile.getName())
    if (oldFile != null && oldFile.crc == newFile.crc) {
        return
    }


    boolean usesAot = variant.getName() == 'profile' || variant.getName() == 'release'
    // Only allow certain changes.
    if (!newFile.getName().startsWith('assets/') &&
            !(usesAot && newFile.getName().endsWith('.so'))) {
        if (ignoreChanges) {
            return
        }
        throw new GradleException("Error: Dynamic patching doesn't support changes to ${newFile.getName()}.")
    }

    final String name = newFile.getName()
    if (name.contains("_snapshot_") || name.endsWith(".so")) {
        byte[] oldBytes = oldApk.getInputStream(new ZipEntry(name)).bytes
        byte[] newBytes = newApk.getInputStream(new ZipEntry(name)).bytes
        FileUtils.writeByteArrayToFile(new File(patchDir, name + '.bzdiff40'), BSDiff.bsdiff(oldBytes, newBytes))
    } else {
        FileUtils.writeByteArrayToFile(new File(patchDir, name), newApk.getInputStream(newFile).bytes)
    }

}

final List<String> checksumFiles = [
        'assets/isolate_snapshot_data',
        'assets/isolate_snapshot_instr',
        'assets/flutter_assets/isolate_snapshot_data',
]
CRC32 checksum = new CRC32()
for (String fn in checksumFiles) {
    final ZipEntry oldFile = oldApk.getEntry(fn)
    if (oldFile != null) {
        checksum.update(oldApk.getInputStream(oldFile).bytes)
    }
}
long baselineChecksum = checksum.getValue()


def variantData = variant.getMetaClass().getProperty(variant, 'variantData')
def buildTools = variantData.getScope().getGlobalScope().getAndroidBuilder().getTargetInfo().getBuildTools()
def stdout = new ByteArrayOutputStream()
project.exec {
    commandLine new File(buildTools.getPath(BuildToolInfo.PathId.AAPT)), "dump", "badging", baseLineApk.getAbsolutePath()
    standardOutput = stdout
}

Pattern versionCodePattern = Pattern.compile("versionCode='(.*?)'", Pattern.MULTILINE)
Matcher matcher = versionCodePattern.matcher(stdout.toString())
matcher.find()
String versionCode = matcher.group(1)
if (versionCode == null || versionCode.length() == 0) {
    throw new GradleException("versionCode can't find.")
}

Gson gson = new GsonBuilder().setPrettyPrinting().create()
Map<String, Object> manifestValues = new HashMap<>()
manifestValues.put("baselineChecksum", baselineChecksum)
manifestValues.put("buildNumber", versionCode)
manifestValues.put("patchNumber", System.currentTimeMillis())
String manifestJson = gson.toJson(manifestValues)
FileUtils.writeByteArrayToFile(new File(patchDir, 'manifest.json'), manifestJson.getBytes())
ZipUtil.pack(patchDir, patchFile)
```

这样虽然可以生成了patch，但是还不够完美，我们对生成的patch进行签名

```
SigningConfig signingConfig = project.tasks.findByName("package${variant.name.capitalize()}").signingConfig
File signOut = new File(patchFile.getParentFile(), "signed_" + patchFile.getName())
//sign patch
signZip(project, patchFile, signingConfig, signOut)

if (!signOut.exists()) {
    throw new GradleException("signed patch file is not exist: ${signOut.absolutePath}")
}

/**
 * 签名函数
 */
private static void signZip(Project project, File inFile, SigningConfig signingConfig, File outFile) throws Exception {
    PrivateKey key;
    X509Certificate certificate;
    boolean v1SigningEnabled;
    boolean v2SigningEnabled;
    if (signingConfig != null && signingConfig.isSigningReady()) {
        CertificateInfo certificateInfo = KeystoreHelper.getCertificateInfo(
                signingConfig.getStoreType(),
                Preconditions.checkNotNull(signingConfig.getStoreFile()),
                Preconditions.checkNotNull(signingConfig.getStorePassword()),
                Preconditions.checkNotNull(signingConfig.getKeyPassword()),
                Preconditions.checkNotNull(signingConfig.getKeyAlias()));
        key = certificateInfo.getKey();
        certificate = certificateInfo.getCertificate();
        v1SigningEnabled = signingConfig.isV1SigningEnabled();
        v2SigningEnabled = signingConfig.isV2SigningEnabled();
    } else {
        key = null;
        certificate = null;
        v1SigningEnabled = false;
        v2SigningEnabled = false;
    }
    ApkCreatorFactory.CreationData creationData =
            new ApkCreatorFactory.CreationData(
                    outFile,
                    key,
                    certificate,
                    v1SigningEnabled,
                    v2SigningEnabled,
                    null,
                    null,
                    1,
                    NativeLibrariesPackagingMode.COMPRESSED,
                    new Predicate<String>() {
                        @Override
                        boolean test(String s) {
                            return false
                        }
                    });
    ApkCreator signedJarBuilder
    try {
        boolean keepTimestamps = AndroidGradleOptions.keepTimestampsInApk(project);
        ZFileOptions options = new ZFileOptions();
        options.setNoTimestamps(!keepTimestamps);
        options.setCoverEmptySpaceUsingExtraField(true);
        ThreadPoolExecutor compressionExecutor =
                new ThreadPoolExecutor(
                        0, /* Number of always alive threads */
                        2,
                        100,
                        TimeUnit.MILLISECONDS,
                        new LinkedBlockingDeque<>());
        options.setCompressor(
                new BestAndDefaultDeflateExecutorCompressor(
                        compressionExecutor,
                        options.getTracker(),
                        1.0));
        options.setAutoSortFiles(true);
        ApkZFileCreatorFactory factory = new ApkZFileCreatorFactory(options);
        signedJarBuilder = factory.make(creationData)
        signedJarBuilder.writeZip(
                inFile,
                null,
                null
        );
    } finally {
        if (signedJarBuilder) {
            signedJarBuilder.close()
        }
    }
}
```

执行如下gradle命令即可完成patch的构建并对其进行签名

```
gradlew assembleReleaseFlutterPatch -PbaselineApk=/path/to/baseline.apk 
```

基线apk也可以传入maven坐标

```
gradlew assembleReleaseFlutterPatch -PbaselineApk=x:y:z
```

至此，我们基本完成了基于Gradle的Flutter Patch的构建。

这里我已经将其抽成了一个可用的插件，有兴趣可以见 
 - [https://github.com/lizhangqu/plugin-flutter-patch](https://github.com/lizhangqu/plugin-flutter-patch)


#### 基于Javassist实现定制化需求

前面我们说到，官方的Patch流程，不支持url的自定义，patch文件的下载模式与安装模式的按patch文件粒度的自定义，不支持Patch文件的签名校验，不支持patch的防重复下载等等问题，那么我们有没有办法复用官方的现有逻辑，但又能解决这些问题呢，我们基于Javassist在编译期对其进行字节码修改，从而达到自定义的能力，其实现大致如下：

```
@Override
void accept(String variantName, String path, InputStream inputStream, OutputStream outputStream) {
    if (path?.contains("io/flutter/view/ResourceUpdater.class") && project.getPlugins().hasPlugin("com.android.application")) {

        ClassPool classPool = new ClassPool(true)
        TransformHelper.updateClassPath(classPool, project, variantName)

        def ctClass = classPool.makeClass(inputStream, false)
        if (ctClass.isFrozen()) {
            ctClass.defrost()
        }



        FlutterTransformExtension flutterTransformExtension = project.getExtensions().findByType(FlutterTransformExtension.class)
        def downloadUrlctMethod = ctClass.getDeclaredMethod("buildUpdateDownloadURL")
        if (downloadUrlctMethod != null) {
            downloadUrlctMethod.setBody("""
{
return ${flutterTransformExtension.patchClass}.${flutterTransformExtension.downloadUrlMethod}(context);
}
""")
        }

        def downloadModectMethod = ctClass.getDeclaredMethod("getDownloadMode")
        if (downloadModectMethod != null) {
            downloadModectMethod.setBody("""
{
try {
return io.flutter.view.ResourceUpdater.DownloadMode.valueOf(${
                flutterTransformExtension.patchClass
            }.${
                flutterTransformExtension.downloadModeMethod
            }(context));
} catch (Exception e) {
return io.flutter.view.ResourceUpdater.DownloadMode.ON_RESTART;
}
}
""")
        }

        def installModectMethod = ctClass.getDeclaredMethod("getInstallMode")
        if (installModectMethod != null) {
            installModectMethod.setBody("""
{
try {
return io.flutter.view.ResourceUpdater.InstallMode.valueOf(${
                flutterTransformExtension.patchClass
            }.${
                flutterTransformExtension.installModeMethod
            }(context));
} catch (Exception e) {
return io.flutter.view.ResourceUpdater.InstallMode.ON_NEXT_RESTART;
}
}
""")
        }

        TransformHelper.copy(new ByteArrayInputStream(ctClass.toBytecode()), outputStream)
    } else {
        TransformHelper.copy(inputStream, outputStream)
    }
}
```


从代码中我们可以看到，我们在编译期用gradle注册一个transform，扫描类，当扫描到 io/flutter/view/ResourceUpdater.class 时，修改其中的三个方法到我们配置的自定义类中，将buildUpdateDownloadURL重定向到自定义类中的获取下载url的方法，将getDownloadMode重定向到自定义类中的获取下载模式的方法，将getInstallMode重定向到自定义类中的获取安装模式的方法。

这里注意一个问题，基于Javassist的字节码修改，我们需要有完整的调用链，因此compile classpath中的类我们必须全部插入到ClassPool类中，如下

```
public static void updateClassPath(ClassPool classPool, Project project, String variantName) {
    getCompileLibraries(project, variantName)?.each {
        try {
            classPool.insertClassPath(it.absolutePath)
        } catch (Exception e) {
        }
    }
    try {
        def javacTask = project.tasks.findByName("compile${variantName.capitalize()}JavaWithJavac")
        classPool.insertClassPath(javacTask.getDestinationDir().getAbsolutePath())
    } catch (Exception e) {
    }
    AppExtension android = project.getExtensions().getByType(AppExtension.class)
    android?.getBootClasspath()?.each {
        try {
            classPool.insertClassPath(it.absolutePath)
        } catch (Exception e) {
        }
    }
}
```

在自定义的类中，我们实现简单的逻辑，对patch的md5进行校验，如果重复，则返回下载的url为null，让其进入异常流程，从而防止重复下载，对于签名校验，我们没有好的方法注入，因此可以在三个自定义方法中分别都进行签名校验，如果校验不通过，则直接删除patch文件，然后再删除时间戳文件，从而让flutter文件重新释放，这里我实现了一个简单的示例，如下

```
@Keep
public class FlutterUpdate {

    @Keep
    public static class FlutterPatch {
        public String url;
        public String md5;
        public String downloadMode;
        public String installMode;

        @Override
        public String toString() {
            return "FlutterPatch{" +
                    "url='" + url + '\'' +
                    ", md5='" + md5 + '\'' +
                    ", downloadMode='" + downloadMode + '\'' +
                    ", installMode='" + installMode + '\'' +
                    '}';
        }
    }

    private static FlutterPatch flutterPatch = null;


    private static String getFileMD5(File file) {
        if (!file.exists()) {
            return null;
        }
        FileInputStream fileInputStream = null;
        try {
            fileInputStream = new FileInputStream(file);
            MessageDigest md5 = MessageDigest.getInstance("MD5");
            byte[] buffer = new byte[1024 * 1024];
            int numRead = 0;
            while ((numRead = fileInputStream.read(buffer)) > 0) {
                md5.update(buffer, 0, numRead);
            }
            return String.format("%032x", new BigInteger(1, md5.digest())).toLowerCase();
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            if (fileInputStream != null) {
                try {
                    fileInputStream.close();
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        }
        return null;
    }


    private static String getInstalledPatchMd5(Context context) {
        File file = new File(context.getFilesDir().toString() + "/patch.zip");
        return getFileMD5(file);
    }

    private static void checkSign(Context context) {
        File file = new File(context.getFilesDir().toString() + "/patch.zip");
        if (!file.exists()) {
            return;
        }
        boolean success = PatchVerify.verifySign(context, file);
        if (!success) {

            //删除patch文件
            file.delete();

            //删除时间戳文件重新释放
            deleteFiles(context);
        }

    }

    private static String[] getExistingTimestamps(File dataDir) {
        return dataDir.list(new FilenameFilter() {
            @Override
            public boolean accept(File dir, String name) {
                return name.startsWith("res_timestamp-");
            }
        });
    }

    private static void deleteFiles(Context context) {
        final File dataDir = new File(context.getDir("flutter", Context.MODE_PRIVATE).getPath());
        final String[] existingTimestamps = getExistingTimestamps(dataDir);
        if (existingTimestamps == null) {
            return;
        }
        for (String timestamp : existingTimestamps) {
            new File(dataDir, timestamp).delete();
        }
    }


    private static void ensureConfig(Context context) {
        if (flutterPatch != null) {
            return;
        }
        //TODO 此处是自定义逻辑，根据本地配置持久化的远程配置，反序列化创建flutterPatch即可，这里mock一个
        FlutterPatch patch = new FlutterPatch();
        patch.url = "下载patch的url";
        patch.md5 = "下载patch的md5";
        patch.downloadMode = "patch的下载模式";
        patch.installMode = "patch的安装模式";

        flutterPatch = patch;

        Log.e("FlutterUpdate", "flutterPatch:" + flutterPatch);

    }

    @Keep
    public static String getDownloadURL(Context context) {
        ensureConfig(context);
        //校验签名，保障文件来源安全
        checkSign(context);
        if (flutterPatch == null) {
            Log.e("FlutterUpdate", "flutterPatch == null");
            return null;
        }
        //校验文件md5，防止patch文件重复下载
        String installedPatchMd5 = getInstalledPatchMd5(context);
        if (installedPatchMd5 != null && installedPatchMd5.equalsIgnoreCase(flutterPatch.md5)) {
            Log.e("FlutterUpdate", "md5 equals:" + flutterPatch.md5);
            return null;
        }

        return flutterPatch.url;
    }

    @Keep
    public static String getDownloadMode(Context context) {
        ensureConfig(context);
        //校验签名，保障文件来源安全
        checkSign(context);
        if (flutterPatch == null) {
            Log.e("FlutterUpdate", "flutterPatch == null");
            return null;
        }

        return flutterPatch.downloadMode;
    }

    @Keep
    public static String getInstallMode(Context context) {
        ensureConfig(context);
        //校验签名，保障文件来源安全
        checkSign(context);
        if (flutterPatch == null) {
            Log.e("FlutterUpdate", "flutterPatch == null");
            return null;
        }

        return flutterPatch.installMode;
    }

}
```

详细代码见 [https://github.com/lizhangqu/plugin-flutter-patch](https://github.com/lizhangqu/plugin-flutter-patch)

### 插件化场景的Flutter插件下发

前面我们已经说到，Flutter是不支持非Flutter代码的修改的，因此对于Android代码及资源的修改它就无能为力了。因此除了官方的Patch下发通道之外，如果App已经是插件化架构的，那么完全可以开辟出基于插件化的插件下发通道来更新Flutter插件，前提是Flutter的所有代码已经是单独的一个bundle了。

不过Flutter代码中有一个关键的地方，导致了插件下发通道会失效。前面我们分析了Flutter的时间戳文件的格式，在没有patch的情况下，它的格式如下

```
res_timestamp-$versionCode-$appLastInstallTime
```

可以看到，时间戳是和app的versionCode和安装时间强关联的，这时候即使我们下发了一个完整的Flutter插件，其实Flutter相关的产物文件也无法能到释放，因为versionCode和安装时间都没有发生变化，flutter会认为当前释放的文件已经是最新的。

基于此，我们必须让Flutter的产物文件释放到一个和插件版本强关联的目录。

现有的Flutter产物会释放到如下目录

```
/data/data/$pkgName/app_flutter

```

假如我们插件的安装目录为

```
/data/data/$pkgName/app_plugins/$bundlePkgName/$bundleVersion
```

那我们需要将现有释放的目录修改为

```
/data/data/$pkgName/app_plugins/$bundlePkgName/$bundleVersion/app_flutter
```

从而让其产物目录和插件化的插件版本强关联，这样以来，一旦下发了新版本的插件，Flutter的产物也就可以得到释放。

我们可以和修改flutter的下载url，下载模式，安装模式的方式类似，通过编译期改字节码的方式重定向产物目录到另外的一个目录。

幸运的是，现有Flutter的释放目录，已经全部收敛到一个类中，如下

```
public final class PathUtils {
    public static String getFilesDir(Context applicationContext) {
        return applicationContext.getFilesDir().getPath();
    }

    public static String getDataDirectory(Context applicationContext) {
        return applicationContext.getDir("flutter", Context.MODE_PRIVATE).getPath();
    }

    public static String getCacheDirectory(Context applicationContext) {
        return applicationContext.getCacheDir().getPath();
    }
}
```

我们只需要修改getDataDirectory函数到自定义的函数中即可，参考代码如下

```
@Override
void accept(String variantName, String path, InputStream inputStream, OutputStream outputStream) {
    if (path?.contains("io/flutter/util/PathUtils.class") && project.getPlugins().hasPlugin("com.android.application")) {

        ClassPool classPool = new ClassPool(true)
        TransformHelper.updateClassPath(classPool, project, variantName)

 		BaseVariant foundVariant = null

        def variants = null;
        if (project.plugins.hasPlugin('com.android.application')) {
            variants = project.android.getApplicationVariants()
        } else if (project.plugins.hasPlugin('com.android.library')) {
            variants = project.android.getLibraryVariants()
        }

        variants?.all { BaseVariant variant ->
            if (variant.getName() == variantName) {
                foundVariant = variant
            }
        }
        if (foundVariant == null) {
            throw new GradleException("variant ${variantName} not found")
        }

        def variantData = foundVariant.getMetaClass().getProperty(foundVariant, 'variantData')
        String bundleName = variantData.getApplicationId()

        def ctClass = classPool.makeClass(inputStream, false)
        if (ctClass.isFrozen()) {
            ctClass.defrost()
        }

        def ctMethod = ctClass.getDeclaredMethod("getDataDirectory")
        //此处根据自己的插件化框架自定义进行修改，这里给出简单的示例
        //$1表示第一个入参，即Context对象
        if (ctMethod != null) {
            ctMethod.setBody("""
{
Bundle bundle = BundleManager.getInstance(\$1).getBundle("$bundleName");
String installDir = BundleManager.getInstallDir(\$1, bundle);
java.io.File file = new java.io.File(installDir, "app_flutter");
if(!file.exists()) {
	file.mkdirs();
}
return file.getAbsolutePath();
}
""")
        }
        TransformHelper.copy(new ByteArrayInputStream(ctClass.toBytecode()), outputStream)
    } else {
        TransformHelper.copy(inputStream, outputStream)
    }
}
```

至此，插件化场景下的Flutter插件下发通道也完全搞定。

### 总结

Flutter 动态下发目前虽然官方已经支持了，但从代码中可以看出，目前的方式是不成熟的，考虑到现状，我们基于字节码修改技术，给Flutter打了几个小小的补丁，从而让其更适应我们的业务场景，而官方的Patch构建方式对gradle的支持也不是很完善，我们则仿造现有的Dart代码，重写了一套基于Gradle构建的Patch构建方式解决这个问题。由此看来Flutter需要走的路还很长。