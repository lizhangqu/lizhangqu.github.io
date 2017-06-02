title: 当Android开发者遇见TensorFlow
date: 2017-06-02 20:14:52
categories: [TensorFlow]
tags: [TensorFlow, 机器学习，Android]
---

### 前言

当写下这篇文章的时候，其实我连TensorFlow怎么用都不会，所以这篇文章你们就当我放屁好了。我是一个Android开发者，且我不会python（别鄙视我），所以取名为《当Android开发者遇见TensorFlow》。文章并没有什么实质性内容，仅仅是为了敲开机器学习的大门。

<!-- more -->

### Java调用TensorFlow

前面说了，本宝宝是一只不会python的宝宝，所以这篇文章不会涉及到任何python相关的内容，所以Java自然而然地成为了我的首选语言。

Google开源的TensorFlow的核心代码是C++写的，因此Java自然而然的可以使用他，只是中间多了一层JNI。加上平时我对Gradle的接触程度，选择Gradle做构建工具，而不是maven。

这里不得不再赞一下Intellij Idea，今天突然发现2017.1版本的Intellij Idea已经能够自动将maven依赖转换为gradle依赖了，我们直接复制maven依赖到gradle中，它就会自动转换为gradle依赖，再也不用我们手动转换。见证奇迹的时候到了


![maven2gradle.gif](maven2gradle.gif)

maven 依赖

```
<dependency>
  <groupId>org.tensorflow</groupId>
  <artifactId>tensorflow</artifactId>
  <version>1.1.0</version>
</dependency>
```

转换后的gradle依赖为

```
dependencies {
    compile 'org.tensorflow:tensorflow:1.1.0'
}
```

为了运行java程序，应用application插件，并制定mainClassName，对应的类在后文创建

```
apply plugin: 'application'
apply plugin: 'idea'
mainClassName = "com.lizhangqu.application.Main"
sourceCompatibility = 1.8
dependencies {
    compile 'org.tensorflow:tensorflow:1.1.0'
}
```

来点有难度的，参考[LabelImage.java](https://github.com/tensorflow/tensorflow/blob/r1.1/tensorflow/java/src/main/java/org/tensorflow/examples/LabelImage.java)，我们来做一个图片识别工具

首先下载训练好的模型 [inception5h.zip](https://storage.googleapis.com/download.tensorflow.org/models/inception5h.zip)，将模型内容解压到src/main/resources/model目录，如图

![model.png](model.png)

然后随便下载一张图作为待识别的图，这里使用这张图，好大一座山

![moutain.jpg](moutain.jpg)

将其放到src/main/resources/pic目录，如图

![pic.png](pic.png)

然后新建一个Main类，拷贝一波[LabelImage.java代码](https://github.com/tensorflow/tensorflow/blob/r1.1/tensorflow/java/src/main/java/org/tensorflow/examples/LabelImage.java)，修改其main函数为

```
public static void main(String[] args) {
    //模型下载
    //https://storage.googleapis.com/download.tensorflow.org/models/inception5h.zip
    String modelPath = Main.class.getClassLoader().getResource("model").getPath();
    String picPath = Main.class.getClassLoader().getResource("pic").getPath();
    byte[] graphDef = readAllBytesOrExit(Paths.get(modelPath, "tensorflow_inception_graph.pb"));
    List<String> labels =
            readAllLinesOrExit(Paths.get(modelPath, "imagenet_comp_graph_label_strings.txt"));
    byte[] imageBytes = readAllBytesOrExit(Paths.get(picPath, "moutain.jpg"));

    try (Tensor image = constructAndExecuteGraphToNormalizeImage(imageBytes)) {
        float[] labelProbabilities = executeInceptionGraph(graphDef, image);
        int bestLabelIdx = maxIndex(labelProbabilities);
        System.out.println(
                String.format(
                        "BEST MATCH: %s (%.2f%% likely)",
                        labels.get(bestLabelIdx), labelProbabilities[bestLabelIdx] * 100f));
    }
}
```

做的修改很简单，将参数从外部传入，修改为了从resources目录读取


Main类完整代码如下

```
package com.lizhangqu.application;

import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.List;

import org.tensorflow.DataType;
import org.tensorflow.Graph;
import org.tensorflow.Output;
import org.tensorflow.Session;
import org.tensorflow.Tensor;

public class Main {

    public static void main(String[] args) {
        //模型下载
        //https://storage.googleapis.com/download.tensorflow.org/models/inception5h.zip
        String modelPath = Main.class.getClassLoader().getResource("model").getPath();
        String picPath = Main.class.getClassLoader().getResource("pic").getPath();
        byte[] graphDef = readAllBytesOrExit(Paths.get(modelPath, "tensorflow_inception_graph.pb"));
        List<String> labels =
                readAllLinesOrExit(Paths.get(modelPath, "imagenet_comp_graph_label_strings.txt"));
        byte[] imageBytes = readAllBytesOrExit(Paths.get(picPath, "moutain.jpg"));

        try (Tensor image = constructAndExecuteGraphToNormalizeImage(imageBytes)) {
            float[] labelProbabilities = executeInceptionGraph(graphDef, image);
            int bestLabelIdx = maxIndex(labelProbabilities);
            System.out.println(
                    String.format(
                            "BEST MATCH: %s (%.2f%% likely)",
                            labels.get(bestLabelIdx), labelProbabilities[bestLabelIdx] * 100f));
        }
    }

    private static Tensor constructAndExecuteGraphToNormalizeImage(byte[] imageBytes) {
        try (Graph g = new Graph()) {
            GraphBuilder b = new GraphBuilder(g);
            // Some constants specific to the pre-trained model at:
            // https://storage.googleapis.com/download.tensorflow.org/models/inception5h.zip
            //
            // - The model was trained with images scaled to 224x224 pixels.
            // - The colors, represented as R, G, B in 1-byte each were converted to
            //   float using (value - Mean)/Scale.
            final int H = 224;
            final int W = 224;
            final float mean = 117f;
            final float scale = 1f;

            // Since the graph is being constructed once per execution here, we can use a constant for the
            // input image. If the graph were to be re-used for multiple input images, a placeholder would
            // have been more appropriate.
            final Output input = b.constant("input", imageBytes);
            final Output output =
                    b.div(
                            b.sub(
                                    b.resizeBilinear(
                                            b.expandDims(
                                                    b.cast(b.decodeJpeg(input, 3), DataType.FLOAT),
                                                    b.constant("make_batch", 0)),
                                            b.constant("size", new int[]{H, W})),
                                    b.constant("mean", mean)),
                            b.constant("scale", scale));
            try (Session s = new Session(g)) {
                return s.runner().fetch(output.op().name()).run().get(0);
            }
        }
    }

    private static float[] executeInceptionGraph(byte[] graphDef, Tensor image) {
        try (Graph g = new Graph()) {
            g.importGraphDef(graphDef);
            try (Session s = new Session(g);
                 Tensor result = s.runner().feed("input", image).fetch("output").run().get(0)) {
                final long[] rshape = result.shape();
                if (result.numDimensions() != 2 || rshape[0] != 1) {
                    throw new RuntimeException(
                            String.format(
                                    "Expected model to produce a [1 N] shaped tensor where N is the number of labels, instead it produced one with shape %s",
                                    Arrays.toString(rshape)));
                }
                int nlabels = (int) rshape[1];
                return result.copyTo(new float[1][nlabels])[0];
            }
        }
    }

    private static int maxIndex(float[] probabilities) {
        int best = 0;
        for (int i = 1; i < probabilities.length; ++i) {
            if (probabilities[i] > probabilities[best]) {
                best = i;
            }
        }
        return best;
    }

    private static byte[] readAllBytesOrExit(Path path) {
        try {
            return Files.readAllBytes(path);
        } catch (IOException e) {
            System.err.println("Failed to read [" + path + "]: " + e.getMessage());
            System.exit(1);
        }
        return null;
    }

    private static List<String> readAllLinesOrExit(Path path) {
        try {
            return Files.readAllLines(path, Charset.forName("UTF-8"));
        } catch (IOException e) {
            System.err.println("Failed to read [" + path + "]: " + e.getMessage());
            System.exit(0);
        }
        return null;
    }

    // In the fullness of time, equivalents of the methods of this class should be auto-generated from
    // the OpDefs linked into libtensorflow_jni.so. That would match what is done in other languages
    // like Python, C++ and Go.
    static class GraphBuilder {
        GraphBuilder(Graph g) {
            this.g = g;
        }

        Output div(Output x, Output y) {
            return binaryOp("Div", x, y);
        }

        Output sub(Output x, Output y) {
            return binaryOp("Sub", x, y);
        }

        Output resizeBilinear(Output images, Output size) {
            return binaryOp("ResizeBilinear", images, size);
        }

        Output expandDims(Output input, Output dim) {
            return binaryOp("ExpandDims", input, dim);
        }

        Output cast(Output value, DataType dtype) {
            return g.opBuilder("Cast", "Cast").addInput(value).setAttr("DstT", dtype).build().output(0);
        }

        Output decodeJpeg(Output contents, long channels) {
            return g.opBuilder("DecodeJpeg", "DecodeJpeg")
                    .addInput(contents)
                    .setAttr("channels", channels)
                    .build()
                    .output(0);
        }

        Output constant(String name, Object value) {
            try (Tensor t = Tensor.create(value)) {
                return g.opBuilder("Const", name)
                        .setAttr("dtype", t.dataType())
                        .setAttr("value", t)
                        .build()
                        .output(0);
            }
        }

        private Output binaryOp(String type, Output in1, Output in2) {
            return g.opBuilder(type, type).addInput(in1).addInput(in2).build().output(0);
        }

        private Graph g;
    }
}

```

跑一波，命令行执行

```
./gradlew run
```

看下输出内容

![run.png](run.png)

输出为

```
BEST MATCH: alp (58.23% likely)
```

我擦，alp是什么鬼，查下英文字典

```
alp 英 [ælp] 美 [ælp] 　 　
n. 高山
```

恩，没错，58.23%的概率这张图是大山。没错，这张图就是大山。当然识别的图的准确率跟这个训练好的模型直接相关，模型越屌，准确率就越高。具体代码什么意思你也别问我，问我我也不知道，文章开头已经说过了，写下这篇文章的时候，我还不会用TensorFlow。

### Android调用TensorFlow

Java能调用，Android自然在一定程度上也能调用。

引入依赖

```
compile 'org.tensorflow:tensorflow-android:1.2.0-rc0'
```

将minSdkVersion设成19，因为用到了高Api，当然如果你想设成14，自行将高Api的代码删了，主要是android.os.Trace类，去除了不影响正常使用

```
android {
    defaultConfig {
        minSdkVersion 19
    }
}
```

还是一样的训练模型，这次把他们扔到assets/model下，待识别的图片放在assets/pic下，如图

![android_model.png](android_model.png)

不过这次我们待识别的图换了，换成了一个大苹果

![apple.jpg](apple.jpg)

还是拷贝点代码，到[android/demo](https://github.com/tensorflow/tensorflow/tree/master/tensorflow/examples/android/src/org/tensorflow/demo)下，拷贝[Classifier.java](https://github.com/tensorflow/tensorflow/blob/master/tensorflow/examples/android/src/org/tensorflow/demo/Classifier.java)和[TensorFlowImageClassifier.java](https://github.com/tensorflow/tensorflow/blob/master/tensorflow/examples/android/src/org/tensorflow/demo/TensorFlowImageClassifier.java)两个类，代码就不贴了。

然后参考下[ClassifierActivity.java](https://github.com/tensorflow/tensorflow/blob/master/tensorflow/examples/android/src/org/tensorflow/demo/ClassifierActivity.java)的代码，将assets/pic/apple.jpg进行识别

```
public class MainActivity extends AppCompatActivity {
    private TextView result;
    private Button btn;
    private Classifier classifier;
    private static final int INPUT_SIZE = 224;
    private static final int IMAGE_MEAN = 117;
    private static final float IMAGE_STD = 1;
    private static final String INPUT_NAME = "input";
    private static final String OUTPUT_NAME = "output";

    private static final String MODEL_FILE = "file:///android_asset/model/tensorflow_inception_graph.pb";
    private static final String LABEL_FILE =
            "file:///android_asset/model/imagenet_comp_graph_label_strings.txt";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        btn = (Button) findViewById(R.id.btn);
        result = (TextView) findViewById(R.id.result);
        classifier = TensorFlowImageClassifier.create(
                getAssets(),
                MODEL_FILE,
                LABEL_FILE,
                INPUT_SIZE,
                IMAGE_MEAN,
                IMAGE_STD,
                INPUT_NAME,
                OUTPUT_NAME);
        btn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {

                new Thread(new Runnable() {
                    @Override
                    public void run() {
                        try {
                            Bitmap croppedBitmap = getBitmap(getApplicationContext(), "pic/apple.jpg", INPUT_SIZE);
                            final List<Classifier.Recognition> results = classifier.recognizeImage(croppedBitmap);
                            new Handler(Looper.getMainLooper()).post(new Runnable() {
                                @Override
                                public void run() {
                                    result.setText("results:" + results);
                                }
                            });
                        } catch (IOException e) {
                            e.printStackTrace();
                        }
                    }
                }).start();
            }
        });
    }

    private static Bitmap getBitmap(Context context, String path, int size) throws IOException {
        Bitmap bitmap = null;
        InputStream inputStream = null;
        inputStream = context.getAssets().open(path);
        bitmap = BitmapFactory.decodeStream(inputStream);
        inputStream.close();
        int width = bitmap.getWidth();
        int height = bitmap.getHeight();
        float scaleWidth = ((float) size) / width;
        float scaleHeight = ((float) size) / height;
        Matrix matrix = new Matrix();
        matrix.postScale(scaleWidth, scaleHeight);
        return Bitmap.createBitmap(bitmap, 0, 0, width, height, matrix, true);
    }

}

```

识别结果如下:

![android_result.png](android_result.png)

识别率最高的是granny smith，什么意思呢，查一下发现是“青苹果”，哭笑不得，这是一个红苹果，这么小的训练模型，也不期待识别率有多高了。


### NDK交叉编译TensorFlow

上面我们用了org.tensorflow:tensorflow-android:1.2.0-rc0这个库，还是得掌握下它的由来，下面我们就编译他。

tensorflow使用bazel构建，且依赖一些python库，因此先安装它们

```
$ brew install bazel
$ brew install swig
$ brew install python
$ sudo easy_install pip
$ sudo pip install six numpy wheel 
```

如果后面报各种各样的环境缺失，请自行Google并补齐环境。


#### clone TensorFlow 代码

```
git clone --recurse-submodules https://github.com/tensorflow/tensorflow.git
```

#### 修改TensorFlow项目根下的WROKSPACE文件

将以下代码反注释

```
# Uncomment and update the paths in these entries to build the Android demo.
android_sdk_repository(
    name = "androidsdk",
    api_level = 23,
    # Ensure that you have the build_tools_version below installed in the
    # SDK manager as it updates periodically.
    build_tools_version = "25.0.2",
    # Replace with path to Android SDK on your system
    path = "/Users/lizhangqu/AndroidSDK",
)
#
# Android NDK r12b is recommended (higher may cause issues with Bazel)
android_ndk_repository(
    name="androidndk",
    path="/Users/lizhangqu/AndroidNDK/android-ndk-r12b",
    # This needs to be 14 or higher to compile TensorFlow.
    # Note that the NDK version is not the API level.
    api_level=14)
```

然后修改android_sdk_repository中的path为自己电脑中的android sdk目录，修改android_ndk_repository中的path为自己电脑的android ndk目录。

值得注意的是，ndk的版本，官方建议使用r12b版本，事实证明，我用android sdk下的ndk-bundle是编译不过去的，所以还是老老实实用r12b，下载地址[android-ndk-r12b-darwin-x86_64.zip](https://dl.google.com/android/repository/android-ndk-r12b-darwin-x86_64.zip?hl=zh-cn
)


#### 编译C++部分代码

```
bazel build -c opt //tensorflow/contrib/android:libtensorflow_inference.so \
   --crosstool_top=//external:android/crosstool \
   --host_crosstool_top=@bazel_tools//tools/cpp:toolchain \
   --cpu=armeabi-v7a
```

如果你需要构建其他cpu结构的so，请自行修改armeabi-v7a为对应的值，比如修改为x86_64

构建好的so位于 bazel-bin/tensorflow/contrib/android/libtensorflow_inference.so，如图所示

![so.png](so.png)

将libtensorflow_inference.so拷贝出来备份起来，因为下一步构建java代码时，此文件会被删除。


#### 编译java部分代码

```
bazel build //tensorflow/contrib/android:android_tensorflow_inference_java
```

编译好的jar位于 bazel-bin/tensorflow/contrib/android/libandroid_tensorflow_inference_java.jar，如图所示

![java.png](java.png)

然后将libandroid_tensorflow_inference_java.jar和libtensorflow_inference.so结合起来，发布到maven，就是我们依赖的org.tensorflow:tensorflow-android:1.2.0-rc0了。


### 编译PC上的Java版TensorFlow

不多说，和NDK交叉编译差不多，编译脚本

```
./configure
bazel build --config opt \
  //tensorflow/java:tensorflow \
  //tensorflow/java:libtensorflow_jni
```

编译产物位于bazel-bin/tensorflow/java，该目录下有

 - libtensorflow.jar文件
 - libtensorflow_jni.so(linux)或libtensorflow_jni.dylib(mac)或tensorflow_jni.dll(windows，注：mac无法编译出dll)文件，

如图所示

 ![pc.png](pc.png)

编译时依赖，请添加libtensorflow.jar
```
javac -cp bazel-bin/tensorflow/java/libtensorflow.jar ...
```

运行期依赖，请添加libtensorflow.jar和libtensorflow_jni的路径
```
java -cp bazel-bin/tensorflow/java/libtensorflow.jar \
  -Djava.library.path=bazel-bin/tensorflow/java \
  ...
```


### 总结

当然一般情况下，我们没有必要自己去编译TensorFlow，只需要使用编译好的现成库即可。

写了这么多，可是宝宝还是不会TensorFlow~