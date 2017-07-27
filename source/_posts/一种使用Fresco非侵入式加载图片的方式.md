title: 一种使用Fresco非侵入式加载图片的方式
date: 2017-07-27 13:07:43
categories: [Android]
tags: [Android, Fresco, ImageLoader]

---

### 前言

Fresco有多叼我就不说了！

<!-- more -->

###  SimpleDraweeView的不足

用过**Fresco**的同学都知道，使用它有一定的成本，必须把所有**ImageView**替换为**SimpleDraweeView**，且是侵入布局式的修改。

稍微好一点的方式是修改项目中的**ImageView**的继承关系。如下：

在一些大型项目中，可能业务上并没有直接在布局中使用**android.widget.ImageView**，而是自定义一层，实现业务上的部分需求（**如webp转换/降级支持，宽高裁剪支持等等**），同时方便到时候可直接通过修改继承关系来随意替换图片库，如下：

```java
public class MyImageView extends ImageView {
    public MyImageView(Context context) {
        super(context);
        init();
    }
  
    public MyImageView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    public MyImageView(Context context, @Nullable AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        init();
    }

    private void init() {

    }

}
```

在布局里并不是直接使用**android.widget.ImageView**，而是使用**MyImageView**

```xml
<io.github.lizhangqu.sample.MyImageView
    android:layout_width="100dp"
    android:layout_height="100dp"/>
```

所以这种方式使用**Fresco**，只需要将**MyImageView**的继承关系修改为继承**SimpleDraweeView**即可，无需改动业务代码。

事物总是有两面性的，这种方式虽然有其优点，但是也有弊端，就是用到图片加载的地方，都必须使用**MyImageView**而不是**ImageView**（虽然**SimpleDraweeView**也一样）。但是他比直接在布局中使用**SimpleDraweeView**要很多，收敛了图片的入口，方便替换。还有一点就是各个基础库得依赖这个继承了的View。

### 图片选择器引发的问题

最近想把项目中的图片选择器给换掉，因为目前使用的图片选择器效果并不是很好，代码修改自github上一个项目[ImageChoose](https://github.com/hongwangsong/ImageChoose)，项目比较老，目前已经没人维护了。于是打算换一个图片选择器，而前段时间，知乎刚好开源了一个图片选择器，就拿它开刀了，项目地址 [Matisse](https://github.com/zhihu/Matisse)。

将项目clone下来一看，懵逼了，没有对**Fresco**的支持，而项目中使用的是**Fresco**，总不能因为一个图片选择器引入两套图片库吧，这就是坑爹的做法。于是看了下issue，发现还是有很多这样的诉求的，如下：

- [Why not add FrescoEngine?](https://github.com/zhihu/Matisse/issues/113)
- [建议支持下fresco](https://github.com/zhihu/Matisse/issues/119)
- [How to support for Fresco?](https://github.com/zhihu/Matisse/issues/141)

看一个回复

> [@Logan676](https://github.com/logan676) As you said, why not add FrescoEngine? I've asked myself the same question. The truth is that Fresco has a lot of customizations, it defines its own view which is `SimpleDraweeView`. So, if we want to support Fresco, it's not that simple you just implement `ImageEngine`, a lot more work needed.

看来知乎不支持Fresco也是有原因的。

### 寻找解决方式

是否存在一种不使用**SimpleDraweeView**而能加载图片的方式，通过查看文档 [writing-custom-views](https://www.fresco-cn.org/docs/writing-custom-views.html) 可以发现，**Fresco**是支持自定义View的。主要需要处理以下几件事情

- 处理好**DraweeHolder**的**attach**/**detach**事件
- 如果开启了加载失败点击重试的功能，需要处理好**View**的**onTouchEvent**事件
- **DraweeHolder**和**DraweeHierarchy**对象的创建尽量只创建一次，因为开销比较大
- 通过**DraweeHolder.getTopLevelDrawable()**方法可以拿到**Drawable**对象，直接使用即可，但是你不能随意的变换这个**Drawable**对象

但是我们现在没有继承**ImageView**，所以没办法处理**attach**/**detach**事件，唯一可行的就是**View.OnAttachStateChangeListener**事件

```java
//remove listener if needed
targetView.removeOnAttachStateChangeListener(mDraweeHolderDispatcher);
//if is already attached, call method onViewAttachedToWindow.
if (isAttachedToWindow(targetView)) {
	mDraweeHolderDispatcher.onViewAttachedToWindow(targetView);
}
//add attach state change listener
targetView.addOnAttachStateChangeListener(mDraweeHolderDispatcher);
```

但是在调用**addOnAttachStateChangeListener**前，可能该View已经AttachedToWindow了，因此需要判断是否已经AttachedToWindow了，如果是的话，手动调用一遍**onViewAttachedToWindow**.

对于点击重试的功能，熟悉View的事件机制，就很好办了，如果对View设置了OnTouchListener，那么OnTouchListener会优先于onTouchEvent方法调用

对应的事件分发的代码如下:

```java
ListenerInfo li = mListenerInfo;
if (li != null && li.mOnTouchListener != null
        && (mViewFlags & ENABLED_MASK) == ENABLED
        && li.mOnTouchListener.onTouch(this, event)) {
    result = true;
}

if (!result && onTouchEvent(event)) {
    result = true;
}
```

于是我们直接设置OnTouchListener即可，**注意，这会覆盖已有的OnTouchListener事件，这里是一个坑点**。

```java
targetView.setOnTouchListener(mDraweeHolderDispatcher);
```

mDraweeHolderDispatcher是DraweeHolderDispatcher的实例，其作用主要做各种事件的分发，分发到mDraweeHolder对应的事件上去，其实现如下：

```java
private class DraweeHolderDispatcher implements View.OnAttachStateChangeListener, View.OnTouchListener {

    @Override
    public void onViewAttachedToWindow(View v) {
        if (mDraweeHolder != null) {
            mDraweeHolder.onAttach();
        }
    }

    @Override
    public void onViewDetachedFromWindow(View v) {
        if (mDraweeHolder != null) {
            mDraweeHolder.onDetach();
        }
    }

    @Override
    public boolean onTouch(View v, MotionEvent event) {
        if (mDraweeHolder != null) {
            if (mDraweeHolder.onTouchEvent(event)) {
                return true;
            }
        }
        return false;
    }
}
```

通过翻看SimpleDraweeView及其父类源码，发现Fresco还重写了View的另外两个方法。

```
  @Override
  public void onStartTemporaryDetach() {
    super.onStartTemporaryDetach();
    onDetach();
  }

  @Override
  public void onFinishTemporaryDetach() {
    super.onFinishTemporaryDetach();
    onAttach();
  }
```

这两个方法有什么用呢，参考这篇文章[Android中判断子View从ListView中移除](http://blog.csdn.net/industriously/article/details/53894214)，如果使用了AbstractListView其子类，如ListView或者GridView，你最好处理一下这个问题，因为他们的item被移出屏幕的时候，其detach并没有调用，而是调用onStartTemporaryDetach和onFinishTemporaryDetach。但是RecyclerView不存在这个问题。处理方式如下：

问题的最大阻碍是这两个方法并没有向外分发，唯一的途径就是继承重写，于是牺牲下，让其可有可无吧，如果他存在，我们就调用对应的事件，如果不存在，就无视，也避免了侵入。采用接口的方式，如果传进来的View是我们对应的接口，则让其自己分发这两个事件出来，然后我们调用对应的attch和detach事件。

```
public interface TemporaryDetachListener {

    void onSaveTemporaryDetachListener(TemporaryDetachListener listener);

    void onStartTemporaryDetach(View view);

    void onFinishTemporaryDetach(View view);
}
```

```
//如果view是TemporaryDetachListener的实例，则将mDraweeHolderDispatcher传入，让View持有，然后在对应的方法中外调，外调后在我们的mDraweeHolderDispatcher中分发。
if (targetView instanceof TemporaryDetachListener) {
    ((TemporaryDetachListener) targetView).onSaveTemporaryDetachListener(mDraweeHolderDispatcher);
}
```

对应的ImageView的子类实现如下:

```Java
public class MyImageView extends ImageView implements FrescoLoader.TemporaryDetachListener {
    FrescoLoader.TemporaryDetachListener listener;

    public MyImageView(Context context) {
        super(context);
    }

    public MyImageView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
    }

    public MyImageView(Context context, @Nullable AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
    }

    @Override
    public void onStartTemporaryDetach() {
        super.onStartTemporaryDetach();
        if (this.listener != null) {
            listener.onStartTemporaryDetach(this);
        }

    }

    @Override
    public void onFinishTemporaryDetach() {
        super.onFinishTemporaryDetach();
        if (this.listener != null) {
            listener.onFinishTemporaryDetach(this);
        }
    }

    @Override
    public void onSaveTemporaryDetachListener(FrescoLoader.TemporaryDetachListener listener) {
        this.listener = listener;
    }

    @Override
    public void onStartTemporaryDetach(View view) {
        //empty
    }

    @Override
    public void onFinishTemporaryDetach(View view) {
        //empty
    }
}
```

补充DraweeHolderDispatcher实现

```java
private class DraweeHolderDispatcher implements View.OnAttachStateChangeListener, View.OnTouchListener, TemporaryDetachListener {

    @Override
    public void onViewAttachedToWindow(View v) {
        if (mDraweeHolder != null) {
            mDraweeHolder.onAttach();
        }
    }

    @Override
    public void onViewDetachedFromWindow(View v) {
        if (mDraweeHolder != null) {
            mDraweeHolder.onDetach();
        }
    }

    @Override
    public void onSaveTemporaryDetachListener(TemporaryDetachListener listener) {
        //empty
    }

    @Override
    public void onStartTemporaryDetach(View view) {
        if (mDraweeHolder != null) {
            mDraweeHolder.onDetach();
        }
    }

    @Override
    public void onFinishTemporaryDetach(View view) {
        if (mDraweeHolder != null) {
            mDraweeHolder.onAttach();
        }
    }

    @Override
    public boolean onTouch(View v, MotionEvent event) {
        if (mDraweeHolder != null) {
            if (mDraweeHolder.onTouchEvent(event)) {
                return true;
            }
        }
        return false;
    }
}
```

**值得注意的是，onStartTemporaryDetach和onFinishTemporaryDetach并不是必要的，只有你使用了AbstractListView其子类，你最好处理一下，其他情况无视即可，因此我们姑且就无视他了，上面就当提供一种实现的参考吧。当然，最好的情况就是处理一下咯，也不排除AbstractListView子类之外的类存在这个问题，导致的直接问题就是内存无法及时回收，占用过高**.

此外，我的**御用挖坑小能手**提供了一种黑科技用于检测这两个事件，贴出代码仅供参考。原理是onStartTemporaryDetach的时候view.getParent()为null，那么只要在View的onPreDraw中进行检测，一直往上搜索rootView，找到rootView与view.getRootView()不一致，就说明getParent()为null，中间断了一层关系。虽然是attach状态，但是却拿不到parent，即onStartTemporaryDetach或onFinishTemporaryDetach，如果是正常的attach或者detach，则最终找到的rootView是一致的

```java
/**
 * 兼容abs listview attach/detach 不回调，回调onStartTemporaryDetach/onFinishTemporaryDetach问题
 *
 * @author lizhangqu
 * @version V1.0
 * @since 2017-07-27 15:28
 */
public class ViewCompat {
    public static void addOnAttachStateChangeListener(View view, View.OnAttachStateChangeListener listener) {
        CompatAttachStateChangeListener.addOnAttachStateChangeListener(view, listener);
    }

    private static class CompatAttachStateChangeListener implements View.OnAttachStateChangeListener, ViewTreeObserver.OnPreDrawListener {
        private View mView;
        private View.OnAttachStateChangeListener mListener;
        private boolean myAttached;
        private boolean yourAttached;

        private static void addOnAttachStateChangeListener(View view, View.OnAttachStateChangeListener listener) {
            new CompatAttachStateChangeListener(view, listener);
        }

        CompatAttachStateChangeListener(View view, View.OnAttachStateChangeListener listener) {
            mView = view;
            mListener = listener;
            myAttached = isAttachedToWindow(mView);
            yourAttached = false;
            if (myAttached) mView.getViewTreeObserver().addOnPreDrawListener(this);
            mView.addOnAttachStateChangeListener(this);
            update();
        }

        @Override
        public void onViewAttachedToWindow(View v) {
            if (myAttached) return;
            myAttached = true;
            mView.getViewTreeObserver().addOnPreDrawListener(this);
            update();
        }

        @Override
        public void onViewDetachedFromWindow(View v) {
            if (!myAttached) return;
            myAttached = false;
            mView.getViewTreeObserver().removeOnPreDrawListener(this);
            update();
        }

        @Override
        public boolean onPreDraw() {
            update();
            return true;
        }

        private void update() {
            boolean attached = attach();
            if (yourAttached != attached) {
                yourAttached = attached;
                if (yourAttached) {
                    mListener.onViewAttachedToWindow(mView);
                } else {
                    mListener.onViewDetachedFromWindow(mView);
                }
            }
        }

        private boolean attach() {
            if (myAttached) {
                View root = mView;
                while (true) {
                    ViewParent parent = root.getParent();
                    if (!(parent instanceof View)) break;
                    root = (View) parent;
                }
                if (root == mView.getRootView()) return true;
            }
            return false;
        }

        private boolean isAttachedToWindow(View view) {
            if (Build.VERSION.SDK_INT >= 19) {
                return view.isAttachedToWindow();
            } else {
                return view.getWindowToken() != null;
            }
        }
    }
}

```

就是将onStartTemporaryDetach和onFinishTemporaryDetach事件等效为onViewAttachedToWindow为onViewDetachedFromWindow事件外发，就可以无视onStartTemporaryDetach和onFinishTemporaryDetach事件了。

最终加一个参数控制这种兼容逻辑，等到需要开启时主动传入参数开启，代码如下

```
if (mCompatTemporaryDetach) {
    ViewCompat.addOnAttachStateChangeListener(targetView, mDraweeHolderDispatcher);
} else {
    //if targetView is instanceof TemporaryDetachListener, set TemporaryDetachListener
    //you should override onSaveTemporaryDetachListener(TemporaryDetachListener l) to holder the param TemporaryDetachListener.
    //also override method onStartTemporaryDetach() and onFinishTemporaryDetach() to call the holder's onStartTemporaryDetach() and onFinishTemporaryDetach()
    if (targetView instanceof TemporaryDetachListener) {
        ((TemporaryDetachListener) targetView).onSaveTemporaryDetachListener(mDraweeHolderDispatcher);
    }
    //if is already attached, call method onViewAttachedToWindow.
    if (isAttachedToWindow(targetView)) {
        mDraweeHolderDispatcher.onViewAttachedToWindow(targetView);
    }
    //add attach state change listener
    targetView.addOnAttachStateChangeListener(mDraweeHolderDispatcher);
}
targetView.setOnTouchListener(mDraweeHolderDispatcher); 
```

接着就可以愉快的使用了。

对mDraweeHolder设置了各种参数后，就可以直接调用对应的getTopLevelDrawable方法，返回Drawable对象，将其设置到ImageView上。

```java
//set image drawable
targetView.setImageDrawable(mDraweeHolder.getTopLevelDrawable());
```

最后一个问题，如何保证DraweeHolder对象只创建一遍，并且保证addOnAttachStateChangeListener只会调用一次，实在是太难了，必须牺牲一下，不然不优雅，**注意，这种方式必须牺牲掉View的tag相关的功能，如果你的ImageView用了Tag，那么你的Tag会被我们覆盖，请转移你的Tag相关功能，使用其他方式。**因为为了让View持有DraweeHolder对象，避免重复创建，只能这么做了，先从Tag中取DraweeHolder，如果取不到，则创建，否则，复用现有的DraweeHolder对象。

```java
//we should use tag
if (mDraweeHolder == null) {
    Object tag = targetView.getTag();
    if (tag instanceof DraweeHolder) {
        mDraweeHolder = (DraweeHolder<DraweeHierarchy>) tag;
    }
}
if (mDraweeHolder == null) 
	mDraweeHolder = DraweeHolder.create(null, targetView.getContext());
    if (mDraweeHolderDispatcher == null) {
        mDraweeHolderDispatcher = new DraweeHolderDispatcher();
    }
    targetView.setTag(mDraweeHolder);
} else {
	//reuse
}
```

这些事情搞定了就是参数传递的事情了，将Fresco需要的参数封装成链式接口调用对应的Fresco方法设置即可，其完整实现我已经push到github上，传送门[FrescoLoader.java](https://github.com/lizhangqu/FrescoLoader/blob/master/library/src/main/java/io/github/lizhangqu/fresco/FrescoLoader.java)

这里也贴一下实现，方便查看

```java
//Copyright 2017 区长. All rights reserved.
//
//Redistribution and use in source and binary forms, with or without
//modification, are permitted provided that the following conditions are
//met:
//
//* Redistributions of source code must retain the above copyright
//notice, this list of conditions and the following disclaimer.
//* Redistributions in binary form must reproduce the above
//copyright notice, this list of conditions and the following disclaimer
//in the documentation and/or other materials provided with the
//distribution.
//* Neither the name of Google Inc. nor the names of its
//contributors may be used to endorse or promote products derived from
//this software without specific prior written permission.
//
//THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
//OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
package io.github.lizhangqu.fresco;

import android.content.Context;
import android.graphics.ColorFilter;
import android.graphics.Point;
import android.graphics.PointF;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.StateListDrawable;
import android.net.Uri;
import android.os.Build;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;

import com.facebook.common.util.UriUtil;
import com.facebook.drawee.backends.pipeline.Fresco;
import com.facebook.drawee.backends.pipeline.PipelineDraweeControllerBuilder;
import com.facebook.drawee.controller.ControllerListener;
import com.facebook.drawee.drawable.ScalingUtils;
import com.facebook.drawee.generic.GenericDraweeHierarchy;
import com.facebook.drawee.generic.GenericDraweeHierarchyBuilder;
import com.facebook.drawee.generic.RoundingParams;
import com.facebook.drawee.interfaces.DraweeController;
import com.facebook.drawee.interfaces.DraweeHierarchy;
import com.facebook.drawee.view.DraweeHolder;
import com.facebook.imagepipeline.common.ResizeOptions;
import com.facebook.imagepipeline.request.ImageRequest;
import com.facebook.imagepipeline.request.ImageRequestBuilder;
import com.facebook.imagepipeline.request.Postprocessor;

import java.io.File;
import java.util.Collections;
import java.util.List;

/**
 * fresco图片加载器, https://www.fresco-cn.org/docs/
 * see: https://www.fresco-cn.org/docs/writing-custom-views.html
 * if you use this FrescoLoader, please make sure you have not use the ImageView's tag
 *
 * @author lizhangqu
 * @version V1.0
 * @since 2017-07-26 13:16
 */
public class FrescoLoader {
    private Context mContext;
    private boolean mCompatTemporaryDetach;
    private DraweeHolderDispatcher mDraweeHolderDispatcher;
    private DraweeHolder<DraweeHierarchy> mDraweeHolder;
    private Postprocessor mPostprocessor;
    private ControllerListener mControllerListener;

    private Uri mUri;
    private Uri mLowerUri;
    private ResizeOptions mResizeOptions;
    private float mDesiredAspectRatio;
    private boolean mUseFixedWidth;
    private boolean mAutoRotateEnabled = false;

    private int mFadeDuration;
    private Drawable mPlaceholderDrawable;
    private Drawable mRetryDrawable;
    private Drawable mFailureDrawable;
    private Drawable mProgressBarDrawable;
    private Drawable mBackgroundDrawable;

    /**
     * 缩放方式
     *
     * @param scaleType 支持以下类型参数
     * center 居中无缩放
     * centerCrop 保持宽高比缩小或放大，使得两边都大于或等于显示边界。居中显示
     * focusCrop 同centerCrop, 但居中点不是中点，而是指定的某个点
     * centerInside 使两边都在显示边界内，居中显示。如果图尺寸大于显示边界，则保持长宽比缩小图片。
     * fitCenter 保持宽高比，缩小或者放大，使得图片完全显示在显示边界内。居中显示
     * fitStart 同上。但不居中，和显示边界左上对齐
     * fitEnd 同fitCenter， 但不居中，和显示边界右下对齐
     * fitXY 不保存宽高比，填充满显示边界
     * none 如要使用tile mode显示, 需要设置为none
     */
    private ScalingUtils.ScaleType mPlaceholderScaleType;
    private ScalingUtils.ScaleType mRetryScaleType;
    private ScalingUtils.ScaleType mFailureScaleType;
    private ScalingUtils.ScaleType mProgressScaleType;

    private ScalingUtils.ScaleType mActualImageScaleType;
    private PointF mActualImageFocusPoint;
    private ColorFilter mActualImageColorFilter;
    private RoundingParams mRoundingParams;

    private List<Drawable> mOverlays;
    private Drawable mPressedStateOverlay;

    private boolean mTapToRetryEnabled;
    private boolean mAutoPlayAnimations;
    private boolean mRetainImageOnFailure;
    private boolean mProgressiveRenderingEnabled;
    private boolean mLocalThumbnailPreviewsEnabled;

    private FrescoLoader(Context context) {
        this.mContext = context.getApplicationContext();
        this.mDraweeHolderDispatcher = null;

        this.mDesiredAspectRatio = 0;
        this.mUseFixedWidth = true;
        this.mFadeDuration = GenericDraweeHierarchyBuilder.DEFAULT_FADE_DURATION;

        this.mPlaceholderDrawable = null;
        this.mPlaceholderScaleType = GenericDraweeHierarchyBuilder.DEFAULT_SCALE_TYPE;

        this.mRetryDrawable = null;
        this.mRetryScaleType = GenericDraweeHierarchyBuilder.DEFAULT_SCALE_TYPE;

        this.mFailureDrawable = null;
        this.mFailureScaleType = GenericDraweeHierarchyBuilder.DEFAULT_SCALE_TYPE;

        this.mProgressBarDrawable = null;
        this.mProgressScaleType = GenericDraweeHierarchyBuilder.DEFAULT_SCALE_TYPE;

        this.mActualImageScaleType = GenericDraweeHierarchyBuilder.DEFAULT_ACTUAL_IMAGE_SCALE_TYPE;
        this.mActualImageFocusPoint = null;
        this.mActualImageColorFilter = null;

        this.mBackgroundDrawable = null;
        this.mOverlays = null;
        this.mPressedStateOverlay = null;
        this.mRoundingParams = null;

        this.mTapToRetryEnabled = false;
        this.mAutoPlayAnimations = false;
        this.mRetainImageOnFailure = false;
        this.mProgressiveRenderingEnabled = false;
        this.mLocalThumbnailPreviewsEnabled = false;

        this.mPostprocessor = null;
        this.mControllerListener = null;
        this.mDraweeHolder = null;
    }


    public boolean hasHierarchy() {
        if (mDraweeHolder != null) {
            return mDraweeHolder.hasHierarchy();
        }
        return false;
    }

    public DraweeHierarchy getHierarchy() {
        if (mDraweeHolder != null) {
            return mDraweeHolder.getHierarchy();
        }
        return null;
    }

    public DraweeController getController() {
        if (mDraweeHolder != null) {
            return mDraweeHolder.getController();
        }
        return null;
    }

    public boolean hasController() {
        if (mDraweeHolder != null) {
            return mDraweeHolder.getController() != null;
        }
        return false;
    }

    //****************context start*******************
    public static FrescoLoader with(Context context) {
        if (context == null) {
            throw new IllegalArgumentException("context == null");
        }
        return new FrescoLoader(context);
    }
    //****************context start*******************

    //****************load start*******************
    public FrescoLoader load(Uri uri) {
        this.mUri = uri;
        return this;
    }

    public FrescoLoader load(String uri) {
        return load(Uri.parse(uri));
    }

    public FrescoLoader load(File file) {
        return load(Uri.fromFile(file));
    }

    public FrescoLoader load(int resourceId) {
        return load(
                new Uri.Builder()
                        .scheme(UriUtil.LOCAL_RESOURCE_SCHEME)
                        .path(String.valueOf(resourceId))
                        .build()
        );
    }

    //****************load end*******************


    //**************lowerLoad start**************
    public FrescoLoader lowerLoad(Uri uri) {
        this.mLowerUri = uri;
        return this;
    }

    public FrescoLoader lowerLoad(String uri) {
        return lowerLoad(Uri.parse(uri));
    }

    public FrescoLoader lowerLoad(File file) {
        return lowerLoad(Uri.fromFile(file));
    }

    public FrescoLoader lowerLoad(int resourceId) {
        return lowerLoad(
                new Uri.Builder()
                        .scheme(UriUtil.LOCAL_RESOURCE_SCHEME)
                        .path(String.valueOf(resourceId))
                        .build()
        );
    }
    //**************lowerLoad end****************

    //**************drawable and scaleType start****************
    public FrescoLoader placeholder(Drawable placeholderDrawable) {
        this.mPlaceholderDrawable = placeholderDrawable;
        return this;
    }

    public FrescoLoader placeholder(int placeholderResId) {
        return placeholder(mContext.getResources().getDrawable(placeholderResId));
    }

    public FrescoLoader placeholderScaleType(ImageView.ScaleType scaleType) {
        this.mPlaceholderScaleType = convertToFrescoScaleType(scaleType, GenericDraweeHierarchyBuilder.DEFAULT_SCALE_TYPE);
        return this;
    }

    public FrescoLoader retry(Drawable retryDrawable) {
        this.mRetryDrawable = retryDrawable;
        return this;
    }

    public FrescoLoader retry(int retryResId) {
        return retry(mContext.getResources().getDrawable(retryResId));
    }

    public FrescoLoader retryScaleType(ImageView.ScaleType scaleType) {
        this.mRetryScaleType = convertToFrescoScaleType(scaleType, GenericDraweeHierarchyBuilder.DEFAULT_SCALE_TYPE);
        return this;
    }

    public FrescoLoader failure(Drawable failureDrawable) {
        this.mFailureDrawable = failureDrawable;
        return this;
    }

    public FrescoLoader failure(int failureResId) {
        return failure(mContext.getResources().getDrawable(failureResId));
    }

    public FrescoLoader failureScaleType(ImageView.ScaleType scaleType) {
        this.mFailureScaleType = convertToFrescoScaleType(scaleType, GenericDraweeHierarchyBuilder.DEFAULT_SCALE_TYPE);
        return this;
    }

    public FrescoLoader progressBar(Drawable placeholderDrawable) {
        this.mProgressBarDrawable = placeholderDrawable;
        return this;
    }

    public FrescoLoader progressBar(int progressResId) {
        return progressBar(mContext.getResources().getDrawable(progressResId));
    }

    public FrescoLoader progressBarScaleType(ImageView.ScaleType scaleType) {
        this.mPlaceholderScaleType = convertToFrescoScaleType(scaleType, GenericDraweeHierarchyBuilder.DEFAULT_SCALE_TYPE);
        return this;
    }

    public FrescoLoader backgroundDrawable(Drawable backgroundDrawable) {
        this.mBackgroundDrawable = backgroundDrawable;
        return this;
    }

    public FrescoLoader backgroundDrawable(int backgroundResId) {
        return backgroundDrawable(mContext.getResources().getDrawable(backgroundResId));
    }

    public FrescoLoader actualScaleType(ImageView.ScaleType scaleType) {
        this.mActualImageScaleType = convertToFrescoScaleType(scaleType, GenericDraweeHierarchyBuilder.DEFAULT_ACTUAL_IMAGE_SCALE_TYPE);
        return this;
    }

    public FrescoLoader focusPoint(PointF focusPoint) {
        this.mActualImageFocusPoint = focusPoint;
        return this;
    }
    //**************drawable and scaleType end****************


    //**************overlays start****************
    public FrescoLoader overlays(List<Drawable> overlays) {
        this.mOverlays = overlays;
        return this;
    }

    public FrescoLoader overlay(Drawable overlay) {
        return overlays(overlay == null ? null : Collections.singletonList(overlay));
    }

    public FrescoLoader overlay(int resId) {
        return overlay(mContext.getResources().getDrawable(resId));
    }

    public FrescoLoader pressedStateOverlay(Drawable drawable) {
        if (drawable == null) {
            this.mPressedStateOverlay = null;
        } else {
            StateListDrawable stateListDrawable = new StateListDrawable();
            stateListDrawable.addState(new int[]{android.R.attr.state_pressed}, drawable);
            this.mPressedStateOverlay = stateListDrawable;
        }
        return this;
    }

    public FrescoLoader pressedStateOverlay(int resId) {
        return pressedStateOverlay(mContext.getResources().getDrawable(resId));
    }

    //**************overlays end****************

    //**************colorFilter start****************
    public FrescoLoader colorFilter(ColorFilter colorFilter) {
        this.mActualImageColorFilter = colorFilter;
        return this;
    }
    //**************colorFilter end****************

    //***************RoundingParams start****************

    public FrescoLoader cornersRadius(int radius) {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setCornersRadius(radius);
        return this;
    }

    public FrescoLoader border(int borderColor, float borderWidth) {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setBorder(borderColor, borderWidth);
        return this;
    }

    public FrescoLoader borderColor(int borderColor) {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setBorderColor(borderColor);
        return this;
    }

    public FrescoLoader borderWidth(float borderWidth) {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setBorderWidth(borderWidth);
        return this;
    }

    public FrescoLoader roundAsCircle() {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setRoundAsCircle(true);
        return this;
    }

    public FrescoLoader cornersRadii(float topLeft, float topRight, float bottomRight, float bottomLeft) {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setCornersRadii(topLeft, topRight, bottomRight, bottomLeft);
        return this;
    }

    public FrescoLoader cornersRadii(float[] radii) {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setCornersRadii(radii);
        return this;
    }

    public FrescoLoader overlayColor(int overlayColor) {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setOverlayColor(overlayColor);
        return this;
    }

    public FrescoLoader padding(float padding) {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setPadding(padding);
        return this;
    }


    public FrescoLoader roundingMethodWithOverlayColor() {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setRoundingMethod(RoundingParams.RoundingMethod.OVERLAY_COLOR);
        return this;
    }

    public FrescoLoader roundingMethodWithBitmapOnly() {
        if (this.mRoundingParams == null) {
            this.mRoundingParams = new RoundingParams();
        }
        this.mRoundingParams.setRoundingMethod(RoundingParams.RoundingMethod.BITMAP_ONLY);
        return this;
    }

    //***************RoundingParams end****************

    //***************resize start****************
    public FrescoLoader resize(Point point) {
        this.mResizeOptions = new ResizeOptions(point.x, point.y);
        return this;
    }

    public FrescoLoader resize(int targetWidth, int targetHeight) {
        this.mResizeOptions = new ResizeOptions(targetWidth, targetHeight);
        return this;
    }
    //***************resize end****************

    //***************fadeDuration start****************
    public FrescoLoader fadeDuration(int fadeDuration) {
        this.mFadeDuration = fadeDuration;
        return this;
    }
    //***************fadeDuration end****************

    //***************desiredAspectRatio start****************
    public FrescoLoader desiredAspectRatioWithWidth(float desiredAspectRatio) {
        this.mUseFixedWidth = true;
        this.mDesiredAspectRatio = desiredAspectRatio;
        return this;
    }

    public FrescoLoader desiredAspectRatioWithHeight(float desiredAspectRatio) {
        this.mUseFixedWidth = false;
        this.mDesiredAspectRatio = desiredAspectRatio;
        return this;
    }

    //***************desiredAspectRatio end****************

    //***************boolean start****************
    public FrescoLoader autoRotateEnabled(boolean enabled) {
        this.mAutoRotateEnabled = enabled;
        return this;
    }

    public FrescoLoader autoPlayAnimations(boolean enabled) {
        this.mAutoPlayAnimations = enabled;
        return this;
    }

    public FrescoLoader retainImageOnFailure(boolean enabled) {
        this.mRetainImageOnFailure = enabled;
        return this;
    }

    public FrescoLoader progressiveRenderingEnabled(boolean enabled) {
        this.mProgressiveRenderingEnabled = enabled;
        return this;
    }

    public FrescoLoader localThumbnailPreviewsEnabled(boolean enabled) {
        this.mLocalThumbnailPreviewsEnabled = enabled;
        return this;
    }

    public FrescoLoader tapToRetryEnabled(boolean tapToRetryEnabled) {
        this.mTapToRetryEnabled = tapToRetryEnabled;
        return this;
    }
    //***************boolean end****************

    //use fresco class method
    //you'd better not use
    @Deprecated
    public FrescoLoader postProcessor(Postprocessor postProcessor) {
        this.mPostprocessor = postProcessor;
        return this;
    }

    //you'd better not use
    @Deprecated
    public FrescoLoader controllerListener(ControllerListener controllerListener) {
        this.mControllerListener = controllerListener;
        return this;
    }

    /**
     * 兼容listview的onStartTemporaryDetach和onFinishTemporaryDetach
     *
     * @param compatTemporaryDetach
     * @return
     */
    public FrescoLoader compatTemporaryDetach(boolean compatTemporaryDetach) {
        this.mCompatTemporaryDetach = compatTemporaryDetach;
        return this;
    }


    //load into an ImageView
    public void into(ImageView targetView) {
        if (targetView == null) {
            return;
        }
        if (mUri == null) {
            return;
        }

        //we should use tag
        if (mDraweeHolder == null) {
            Object tag = targetView.getTag();
            if (tag instanceof DraweeHolder) {
                mDraweeHolder = (DraweeHolder<DraweeHierarchy>) tag;
            }
        }
        if (mDraweeHolder == null) {
            mDraweeHolder = DraweeHolder.create(null, targetView.getContext());
            if (mDraweeHolderDispatcher == null) {
                mDraweeHolderDispatcher = new DraweeHolderDispatcher();
            }
            GenericDraweeHierarchy hierarchy = new GenericDraweeHierarchyBuilder(targetView.getResources())
                    .setPlaceholderImage(mPlaceholderDrawable)
                    .setPlaceholderImageScaleType(mPlaceholderScaleType)
                    .setFailureImage(mFailureDrawable)
                    .setFailureImageScaleType(mFailureScaleType)
                    .setProgressBarImage(mProgressBarDrawable)
                    .setProgressBarImageScaleType(mProgressScaleType)
                    .setRetryImage(mRetryDrawable)
                    .setRetryImageScaleType(mRetryScaleType)
                    .setFadeDuration(mFadeDuration)
                    .setActualImageFocusPoint(mActualImageFocusPoint)
                    .setActualImageColorFilter(mActualImageColorFilter)
                    .setActualImageScaleType(mActualImageScaleType)
                    .setBackground(mBackgroundDrawable)
                    .setOverlays(mOverlays)
                    .setPressedStateOverlay(mPressedStateOverlay)
                    .setRoundingParams(mRoundingParams)
                    .build();

            //set hierarchy
            mDraweeHolder.setHierarchy(hierarchy);

            //image request
            ImageRequest request = ImageRequestBuilder.newBuilderWithSource(mUri)
                    .setAutoRotateEnabled(mAutoRotateEnabled)
                    .setLocalThumbnailPreviewsEnabled(mLocalThumbnailPreviewsEnabled)
                    .setPostprocessor(mPostprocessor)
                    .setProgressiveRenderingEnabled(mProgressiveRenderingEnabled)
                    .setResizeOptions(mResizeOptions)
                    .build();

            //controller
            PipelineDraweeControllerBuilder controllerBuilder = Fresco.newDraweeControllerBuilder()
                    .setAutoPlayAnimations(mAutoPlayAnimations)
                    .setControllerListener(mControllerListener)
                    .setImageRequest(request)
                    .setOldController(mDraweeHolder.getController())
                    .setRetainImageOnFailure(mRetainImageOnFailure)
                    .setTapToRetryEnabled(mTapToRetryEnabled);


            //if set the mLowerUri, then pass this param
            if (mLowerUri != null) {
                controllerBuilder.setLowResImageRequest(ImageRequest.fromUri(mLowerUri));
            }
            //build controller
            DraweeController draweeController = controllerBuilder.build();
            //set controller
            mDraweeHolder.setController(draweeController);

            if (mCompatTemporaryDetach) {
                ViewCompat.addOnAttachStateChangeListener(targetView, mDraweeHolderDispatcher);
            } else {
                //if targetView is instanceof TemporaryDetachListener, set TemporaryDetachListener
                //you should override onSaveTemporaryDetachListener(TemporaryDetachListener l) to holder the param TemporaryDetachListener.
                //also override method onStartTemporaryDetach() and onFinishTemporaryDetach() to call the holder's onStartTemporaryDetach() and onFinishTemporaryDetach()
                if (targetView instanceof TemporaryDetachListener) {
                    ((TemporaryDetachListener) targetView).onSaveTemporaryDetachListener(mDraweeHolderDispatcher);
                }
                //if is already attached, call method onViewAttachedToWindow.
                if (isAttachedToWindow(targetView)) {
                    mDraweeHolderDispatcher.onViewAttachedToWindow(targetView);
                }
                //add attach state change listener
                targetView.addOnAttachStateChangeListener(mDraweeHolderDispatcher);
            }
            targetView.setOnTouchListener(mDraweeHolderDispatcher);
            targetView.setTag(mDraweeHolder);
        } else {
            GenericDraweeHierarchy hierarchy = new GenericDraweeHierarchyBuilder(targetView.getResources())
                    .setPlaceholderImage(mPlaceholderDrawable)
                    .setPlaceholderImageScaleType(mPlaceholderScaleType)
                    .setFailureImage(mFailureDrawable)
                    .setFailureImageScaleType(mFailureScaleType)
                    .setProgressBarImage(mProgressBarDrawable)
                    .setProgressBarImageScaleType(mProgressScaleType)
                    .setRetryImage(mRetryDrawable)
                    .setRetryImageScaleType(mRetryScaleType)
                    .setFadeDuration(mFadeDuration)
                    .setActualImageFocusPoint(mActualImageFocusPoint)
                    .setActualImageColorFilter(mActualImageColorFilter)
                    .setActualImageScaleType(mActualImageScaleType)
                    .setBackground(mBackgroundDrawable)
                    .setOverlays(mOverlays)
                    .setPressedStateOverlay(mPressedStateOverlay)
                    .setRoundingParams(mRoundingParams)
                    .build();

            //set hierarchy
            mDraweeHolder.setHierarchy(hierarchy);

            //image request
            ImageRequest request = ImageRequestBuilder.newBuilderWithSource(mUri)
                    .setAutoRotateEnabled(mAutoRotateEnabled)
                    .setLocalThumbnailPreviewsEnabled(mLocalThumbnailPreviewsEnabled)
                    .setPostprocessor(mPostprocessor)
                    .setProgressiveRenderingEnabled(mProgressiveRenderingEnabled)
                    .setResizeOptions(mResizeOptions)
                    .build();

            //controller
            PipelineDraweeControllerBuilder controllerBuilder = Fresco.newDraweeControllerBuilder()
                    .setAutoPlayAnimations(mAutoPlayAnimations)
                    .setControllerListener(mControllerListener)
                    .setImageRequest(request)
                    .setOldController(mDraweeHolder.getController())
                    .setRetainImageOnFailure(mRetainImageOnFailure)
                    .setTapToRetryEnabled(mTapToRetryEnabled);


            //if set the mLowerUri, then pass this param
            if (mLowerUri != null) {
                controllerBuilder.setLowResImageRequest(ImageRequest.fromUri(mLowerUri));
            }
            //build controller
            DraweeController draweeController = controllerBuilder.build();
            //set controller
            mDraweeHolder.setController(draweeController);
        }

        //compat for desiredAspectRatio
        if (mDesiredAspectRatio != 0) {
            ViewGroup.LayoutParams layoutParams = targetView.getLayoutParams();
            if (layoutParams != null) {
                int width = layoutParams.width;
                int height = layoutParams.height;
                int newWidth = -1;
                int newHeight = -1;
                //mDesiredAspectRatio= width/height;
                if (mUseFixedWidth) {
                    //with must > 0 & height=0
                    if (width > 0 && height == 0) {
                        newWidth = width;
                        newHeight = (int) (width * 1.0 / mDesiredAspectRatio + 0.5);
                    }
                } else {
                    //height must > 0 & width=0
                    if (height > 0 && width == 0) {
                        newHeight = height;
                        newWidth = (int) (height * mDesiredAspectRatio + 0.5);
                    }
                }
                if (newWidth != -1 && newHeight != -1) {
                    layoutParams.width = newWidth;
                    layoutParams.height = newHeight;
                    targetView.requestLayout();
                }
            }
        }

        //set image drawable
        targetView.setImageDrawable(mDraweeHolder.getTopLevelDrawable());

    }

    private static boolean isAttachedToWindow(View view) {
        if (Build.VERSION.SDK_INT >= 19) {
            return view.isAttachedToWindow();
        } else {
            return view.getWindowToken() != null;
        }
    }

    private static ScalingUtils.ScaleType convertToFrescoScaleType(ImageView.ScaleType scaleType, ScalingUtils.ScaleType defaultScaleType) {
        switch (scaleType) {
            case CENTER:
                return ScalingUtils.ScaleType.CENTER;
            case CENTER_CROP:
                return ScalingUtils.ScaleType.CENTER_CROP;
            case CENTER_INSIDE:
                return ScalingUtils.ScaleType.CENTER_INSIDE;
            case FIT_CENTER:
                return ScalingUtils.ScaleType.FIT_CENTER;
            case FIT_START:
                return ScalingUtils.ScaleType.FIT_START;
            case FIT_END:
                return ScalingUtils.ScaleType.FIT_END;
            case FIT_XY:
                return ScalingUtils.ScaleType.FIT_XY;
            case MATRIX:
                //NOTE this case
                //you should set FocusPoint to make sentence
                return ScalingUtils.ScaleType.FOCUS_CROP;
            default:
                return defaultScaleType;
        }
    }


    //if needed, let's your image view implement this interface
    //also it's not must be required to implement this interface
    public interface TemporaryDetachListener {

        void onSaveTemporaryDetachListener(TemporaryDetachListener listener);

        void onStartTemporaryDetach(View view);

        void onFinishTemporaryDetach(View view);
    }


    //DraweeHolder event dispatch
    private class DraweeHolderDispatcher implements View.OnAttachStateChangeListener, View.OnTouchListener, TemporaryDetachListener {

        @Override
        public void onViewAttachedToWindow(View v) {
            if (mDraweeHolder != null) {
                mDraweeHolder.onAttach();
            }
        }

        @Override
        public void onViewDetachedFromWindow(View v) {
            if (mDraweeHolder != null) {
                mDraweeHolder.onDetach();
            }
        }

        @Override
        public void onSaveTemporaryDetachListener(TemporaryDetachListener listener) {
            //empty
        }

        @Override
        public void onStartTemporaryDetach(View view) {
            if (mDraweeHolder != null) {
                mDraweeHolder.onDetach();
            }
        }

        @Override
        public void onFinishTemporaryDetach(View view) {
            if (mDraweeHolder != null) {
                mDraweeHolder.onAttach();
            }
        }

        @Override
        public boolean onTouch(View v, MotionEvent event) {
            if (mDraweeHolder != null) {
                if (mDraweeHolder.onTouchEvent(event)) {
                    return true;
                }
            }
            return false;
        }
    }

}
```

### 最后一个坑

当你看到这里的时候，其实还有一个坑，就是虽然DraweeHolder一个View只创建了一个，但是GenericDraweeHierarchy，ImageRequest，PipelineDraweeControllerBuilder等对象还是多次创建了，其实这些也是可以复用的，这里就姑且先不复用了



### 总结

- 牺牲了View的Tag相关功能，如果你用了，必须使用其他方式实现你的Tag相关功能（如果没有使用Tag，那更好了）
- 牺牲了View的OnTouchListener事件（如果没有使用OnTouchListener，那更好了）
- GenericDraweeHierarchy，ImageRequest，PipelineDraweeControllerBuilder等对象的多次创建问题（可继续优化代码，只创建一次，反正我是懒得优化了）
- onStartTemporaryDetach和onFinishTemporaryDetach事件外发的接口侵入性（如果没有使用AbstractListView其子类则可不实现，否则最好将item中使用到的ImageView实现TemporaryDetachListener接口，这不得不加入一层接口实现关系），**可使用mCompatTemporaryDetach参数主动开启黑科技，这样也就不用侵入了**

如果你接受得了以上几点问题，那么就放心使用吧，否则，还是老老实实的用最开头提到的继承关系式去实现。不过这对于实现知乎图片选择器的FrescoEngine已经绰绰有余了。

最后使用FrescoLoader

```Java
FrescoLoader.with(view.getContext())
            .progressiveRenderingEnabled(true)
            .fadeDuration(2000)
            .autoPlayAnimations(true)
            .autoRotateEnabled(true)
            .retainImageOnFailure(true)
            .desiredAspectRatioWithHeight(0.5F)
            .tapToRetryEnabled(true)
            .focusPoint(new PointF(30, 50))
            .resize(400, 400)
            .fadeDuration(1000)
            .border(Color.RED, 10)
            .borderColor(Color.RED)
            .borderWidth(10)
            .cornersRadii(10, 10, 10, 10)
            .cornersRadius(10)
            .roundAsCircle()
            .backgroundDrawable(ContextCompat.getDrawable(getApplicationContext(), R.mipmap.bg_zero))
            .progressBar(ContextCompat.getDrawable(getApplicationContext(), R.mipmap.icon_progress_bar))
            .progressBarScaleType(ImageView.ScaleType.CENTER_CROP)
            .placeholder(ContextCompat.getDrawable(getApplicationContext(), R.mipmap.icon_placeholder))
            .placeholderScaleType(ImageView.ScaleType.CENTER_CROP)
            .failure(ContextCompat.getDrawable(getApplicationContext(), R.mipmap.icon_failure))
            .failureScaleType(ImageView.ScaleType.CENTER_CROP)
            .retry(ContextCompat.getDrawable(getApplicationContext(), R.mipmap.icon_retry))
            .retryScaleType(ImageView.ScaleType.CENTER_CROP)
            .colorFilter(new PorterDuffColorFilter(Color.RED, PorterDuff.Mode.DARKEN))
            .overlays(overlays)
            .pressedStateOverlay(ContextCompat.getDrawable(getApplicationContext(), R.mipmap.bg_one))
            .actualScaleType(ImageView.ScaleType.CENTER_CROP)
            .lowerLoad(R.mipmap.ic_launcher_round)
            .load("http://desk.fd.zol-img.com.cn/t_s960x600c5/g5/M00/0D/01/ChMkJlgq0z-IC78PAA1UbwykJUgAAXxIwMAwQcADVSH340.jpg")
            .localThumbnailPreviewsEnabled(true)
            .into(image);
```

知乎图片选择器Fresco的实现也就很简单了

```Java
public class FrescoEngine implements ImageEngine {
    @Override
    public void loadThumbnail(Context context, int resize, Drawable placeholder, ImageView imageView, Uri uri) {
        FrescoLoader.with(context)
                .placeholder(placeholder)
                .resize(resize, resize)
                .progressiveRenderingEnabled(true)
                .load(uri)
                .fadeDuration(300)
                .actualScaleType(ImageView.ScaleType.CENTER_CROP)
                .into(imageView);
    }

    @Override
    public void loadGifThumbnail(Context context, int resize, Drawable placeholder, ImageView imageView, Uri uri) {
        FrescoLoader.with(context)
                .placeholder(placeholder)
                .resize(resize, resize)
                .progressiveRenderingEnabled(true)
                .load(uri)
                .fadeDuration(300)
                .actualScaleType(ImageView.ScaleType.CENTER_CROP)
                .autoPlayAnimations(true)
                .into(imageView);
    }

    @Override
    public void loadImage(Context context, int resizeX, int resizeY, ImageView imageView, Uri uri) {
        FrescoLoader.with(context)
                .resize(resizeX, resizeY)
                .progressiveRenderingEnabled(true)
                .load(uri)
                .fadeDuration(300)
                .actualScaleType(ImageView.ScaleType.CENTER_CROP)
                .into(imageView);
    }

    @Override
    public void loadGifImage(Context context, int resizeX, int resizeY, ImageView imageView, Uri uri) {
        FrescoLoader.with(context)
                .resize(resizeX, resizeY)
                .progressiveRenderingEnabled(true)
                .load(uri)
                .fadeDuration(300)
                .actualScaleType(ImageView.ScaleType.CENTER_CROP)
                .autoPlayAnimations(true)
                .into(imageView);
    }

    @Override
    public boolean supportAnimatedGif() {
        return true;
    }
}

```

