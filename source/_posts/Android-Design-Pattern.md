title: Android开发中常见的设计模式
tags: [Android,Design Pattern,安卓,设计模式,单例模式,Build模式,观察者模式,原型模式,策略模式]
date: 2015-11-26 12:19:16
categories: Android
description: 设计模式在开发中尤其常见，要写出优良的可扩展的代码，设计模式显得尤其重要，在Android中，无论是系统还是开源框架，涉及到了大量的设计模式，掌握这些设计模式对能力的提升具有显著的作用
---

对于开发人员来说，设计模式有时候就是一道坎，但是设计模式又非常有用，过了这道坎，它可以让你水平提高一个档次。而在android开发中，必要的了解一些设计模式又是非常有必要的。对于想系统的学习设计模式的同学，这里推荐2本书。一本是Head First系列的Head Hirst Design Pattern，英文好的可以看英文，可以多读几遍。另外一本是大话设计模式。


## 单例模式

首先了解一些单例模式的概念。
>确保某一个类只有一个实例，而且自行实例化并向整个系统提供这个实例。

这样做有以下几个优点
 - 对于那些比较耗内存的类，只实例化一次可以大大提高性能，尤其是在移动开发中。
 - 保持程序运行的时候该中始终只有一个实例存在内存中

其实单例有很多种实现方式，但是个人比较倾向于其中1种。可以见[单例模式](https://github.com/iluwatar/java-design-patterns/blob/master/singleton/src/main/java/com/iluwatar/singleton/ThreadSafeDoubleCheckLocking.java)

代码如下

```java
public class Singleton {
    private static volatile Singleton instance = null;

    private Singleton(){
    }
 
    public static Singleton getInstance() {
        if (instance == null) {
            synchronized (Singleton.class) {
                if (instance == null) {
                    instance = new Singleton();
                }
            }
        }
        return instance;
    }
}
```

要保证单例，需要做一下几步

 - 必须防止外部可以调用构造函数进行实例化，因此构造函数必须私有化。
 - 必须定义一个静态函数获得该单例
 - 单例使用volatile修饰
 - 使用synchronized 进行同步处理，并且双重判断是否为null，我们看到synchronized (Singleton.class)里面又进行了是否为null的判断，这是因为一个线程进入了该代码，如果另一个线程在等待，这时候前一个线程创建了一个实例出来完毕后，另一个线程获得锁进入该同步代码，实例已经存在，没必要再次创建，因此这个判断是否是null还是必须的。

至于单例的并发测试，可以使用CountDownLatch，使用await()等待锁释放，使用countDown()释放锁从而达到并发的效果。可以见下面的代码

```java
public static void main(String[] args) {
	final CountDownLatch latch = new CountDownLatch(1);
	int threadCount = 1000;
	for (int i = 0; i < threadCount; i++) {
		new Thread() {
			@Override
			public void run() {
				try {
					latch.await();
				} catch (InterruptedException e) {
					e.printStackTrace();
				}
				System.out.println(Singleton.getInstance().hashCode());
			}
		}.start();
	}
	latch.countDown();
}
```

看看打印出来的hashCode会不会出现不一样即可，理论上是全部都一样的。


而在Android中，很多地方用到了单例。

比如Android-Universal-Image-Loader中的单例

```java
private volatile static ImageLoader instance;
/** Returns singleton class instance */
public static ImageLoader getInstance() {
	if (instance == null) {
		synchronized (ImageLoader.class) {
			if (instance == null) {
				instance = new ImageLoader();
			}
		}
	}
	return instance;
}
```



比如EventBus中的单例

```java
private static volatile EventBus defaultInstance;
public static EventBus getDefault() {
	if (defaultInstance == null) {
		synchronized (EventBus.class) {
			if (defaultInstance == null) {
				defaultInstance = new EventBus();
			}
		}
	}
	return defaultInstance;
}
```

上面的单例都是比较规规矩矩的，当然实际上有很多单例都是变了一个样子，单本质还是单例。

如InputMethodManager 中的单例

```java
static InputMethodManager sInstance;
public static InputMethodManager getInstance() {
	synchronized (InputMethodManager.class) {
		if (sInstance == null) {
			IBinder b = ServiceManager.getService(Context.INPUT_METHOD_SERVICE);
			IInputMethodManager service = IInputMethodManager.Stub.asInterface(b);
			sInstance = new InputMethodManager(service, Looper.getMainLooper());
		}
		return sInstance;
	}
}
```

AccessibilityManager 中的单例，看代码这么长，其实就是进行了一些判断，还是一个单例

```java
private static AccessibilityManager sInstance;
public static AccessibilityManager getInstance(Context context) {
	synchronized (sInstanceSync) {
		if (sInstance == null) {
			final int userId;
			if (Binder.getCallingUid() == Process.SYSTEM_UID
					|| context.checkCallingOrSelfPermission(
							Manifest.permission.INTERACT_ACROSS_USERS)
									== PackageManager.PERMISSION_GRANTED
					|| context.checkCallingOrSelfPermission(
							Manifest.permission.INTERACT_ACROSS_USERS_FULL)
									== PackageManager.PERMISSION_GRANTED) {
				userId = UserHandle.USER_CURRENT;
			} else {
				userId = UserHandle.myUserId();
			}
			IBinder iBinder = ServiceManager.getService(Context.ACCESSIBILITY_SERVICE);
			IAccessibilityManager service = IAccessibilityManager.Stub.asInterface(iBinder);
			sInstance = new AccessibilityManager(context, service, userId);
		}
	}
	return sInstance;
}
```

当然单例还有很多种写法，比如恶汉式，有兴趣的自己去了解就好了。

最后，我们应用一下单例模式。典型的一个应用就是管理我们的Activity，下面这个可以作为一个工具类，代码也很简单，也不做什么解释了。

```java
public class ActivityManager {

	private static volatile ActivityManager instance;
	private Stack<Activity> mActivityStack = new Stack<Activity>();
	
	private ActivityManager(){
		
	}
	
	public static ActivityManager getInstance(){
		if (instance == null) {
		synchronized (ActivityManager.class) {
			if (instance == null) {
				instance = new ActivityManager();
			}
		}
		return instance;
	}
	
	public void addActicity(Activity act){
		mActivityStack.push(act);
	}
	
	public void removeActivity(Activity act){
		mActivityStack.remove(act);
	}
	
	public void killMyProcess(){
		int nCount = mActivityStack.size();
		for (int i = nCount - 1; i >= 0; i--) {
        	Activity activity = mActivityStack.get(i);
        	activity.finish();
        }
		
		mActivityStack.clear();
		android.os.Process.killProcess(android.os.Process.myPid());
	}
}

```

这个类可以在开源中国的几个客户端中找到类似的源码

 - [Git@OSC中的AppManager](http://git.oschina.net/oschina/git-osc-android-project/blob/master/gitoscandroid/src/main/java/net/oschina/gitapp/AppManager.java?dir=0&filepath=gitoscandroid%2Fsrc%2Fmain%2Fjava%2Fnet%2Foschina%2Fgitapp%2FAppManager.java&oid=546475432f6f96677a9715c52308578d520b9fc6&sha=1a9706c0913b0377d216c02f7cedda97e8a20dc1)

 - [android-app中的AppManager](http://git.oschina.net/oschina/android-app/blob/master/app/src/main/java/net/oschina/app/AppManager.java?dir=0&filepath=app%2Fsrc%2Fmain%2Fjava%2Fnet%2Foschina%2Fapp%2FAppManager.java&oid=7e9bbd1811b0667792910fa6e4d88ea00d15bb8c&sha=4e8eb3ebd6fab29aac26732027be95deaeec91de)

以上两个类是一样的，没区别。


## Build模式

了解了[单例模式](#单例模式)，接下来介绍另一个常见的模式——Builder模式。

那么什么是Builder模式呢。你通过搜索，会发现大部分网上的定义都是
>将一个复杂对象的构建与它的表示分离，使得同样的构建过程可以创建不同的表示

但是看完这个定义，并没有什么卵用，你依然不知道什么是Builder设计模式。在此个人的态度是学习设计模式这种东西，不要过度在意其定义，定义往往是比较抽象的，学习它最好的例子就是通过样例代码。

我们通过一个例子来引出Builder模式。假设有一个Person类，我们通过该Person类来构建一大批人，这个Person类里有很多属性，最常见的比如name，age，weight，height等等，并且我们允许这些值不被设置，也就是允许为null，该类的定义如下。

```java
public class Person {
    private String name;
    private int age;
    private double height;
    private double weight;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        this.age = age;
    }

    public double getHeight() {
        return height;
    }

    public void setHeight(double height) {
        this.height = height;
    }

    public double getWeight() {
        return weight;
    }

    public void setWeight(double weight) {
        this.weight = weight;
    }
}
```

然后我们为了方便可能会定义一个构造方法。

```java
public Person(String name, int age, double height, double weight) {
	this.name = name;
	this.age = age;
	this.height = height;
	this.weight = weight;
}

```

或许为了方便new对象，你还会定义一个空的构造方法

```java
public Person() {
}
```

甚至有时候你很懒，只想传部分参数，你还会定义如下类似的构造方法。

```java
public Person(String name) {
	this.name = name;
}

public Person(String name, int age) {
	this.name = name;
	this.age = age;
}

public Person(String name, int age, double height) {
	this.name = name;
	this.age = age;
	this.height = height;
}
```
于是你就可以这样创建各个需要的对象

```java
Person p1=new Person();
Person p2=new Person("张三");
Person p3=new Person("李四",18);
Person p4=new Person("王五",21,180);
Person p5=new Person("赵六",17,170,65.4);
```

可以想象一下这样创建的坏处，最直观的就是四个参数的构造函数的最后面的两个参数到底是什么意思，可读性不怎么好，如果不点击看源码，鬼知道哪个是weight哪个是height。还有一个问题就是当有很多参数时，编写这个构造函数就会显得异常麻烦，这时候如果换一个角度，试试Builder模式，你会发现代码的可读性一下子就上去了。

我们给Person增加一个静态内部类Builder类，并修改Person类的构造函数，代码如下。

```java
public class Person {
    private String name;
    private int age;
    private double height;
    private double weight;

    privatePerson(Builder builder) {
        this.name=builder.name;
        this.age=builder.age;
        this.height=builder.height;
        this.weight=builder.weight;
    }
    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        this.age = age;
    }

    public double getHeight() {
        return height;
    }

    public void setHeight(double height) {
        this.height = height;
    }

    public double getWeight() {
        return weight;
    }

    public void setWeight(double weight) {
        this.weight = weight;
    }

    static class Builder{
        private String name;
        private int age;
        private double height;
        private double weight;
        public Builder name(String name){
            this.name=name;
            return this;
        }
        public Builder age(int age){
            this.age=age;
            return this;
        }
        public Builder height(double height){
            this.height=height;
            return this;
        }

        public Builder weight(double weight){
            this.weight=weight;
            return this;
        }

        public Person build(){
            return new Person(this);
        }
    }
}

```
从上面的代码中我们可以看到，我们在Builder类里定义了一份与Person类一模一样的变量，通过一系列的成员函数进行设置属性值，但是返回值都是this，也就是都是Builder对象，最后提供了一个build函数用于创建Person对象，返回的是Person对象，对应的构造函数在Person类中进行定义，也就是构造函数的入参是Builder对象，然后依次对自己的成员变量进行赋值，对应的值都是Builder对象中的值。此外Builder类中的成员函数返回Builder对象自身的另一个作用就是让它支持链式调用，使代码可读性大大增强。


于是我们就可以这样创建Person类。
```java
Person.Builder builder=new Person.Builder();
Person person=builder
		.name("张三")
		.age(18)
		.height(178.5)
		.weight(67.4)
		.build();
```

有没有觉得创建过程一下子就变得那么清晰了。对应的值是什么属性一目了然，可读性大大增强。

其实在Android中， Builder模式也是被大量的运用。比如常见的对话框的创建

```java
AlertDialog.Builder builder=new AlertDialog.Builder(this);
AlertDialog dialog=builder.setTitle("标题")
		.setIcon(android.R.drawable.ic_dialog_alert)
		.setView(R.layout.myview)
		.setPositiveButton(R.string.positive, new DialogInterface.OnClickListener() {
			@Override
			public void onClick(DialogInterface dialog, int which) {

			}
		})
		.setNegativeButton(R.string.negative, new DialogInterface.OnClickListener() {
			@Override
			public void onClick(DialogInterface dialog, int which) {

			}
		})
		.create();
dialog.show();
```

其实在java中有两个常见的类也是Builder模式，那就是StringBuilder和StringBuffer，只不过其实现过程简化了一点罢了。

我们再找找Builder模式在各个框架中的应用。

如Gson中的GsonBuilder，代码太长了，就不贴了，有兴趣自己去看源码，这里只贴出其Builder的使用方法。

```java
GsonBuilder builder=new GsonBuilder();
Gson gson=builder.setPrettyPrinting()
		.disableHtmlEscaping()
		.generateNonExecutableJson()
		.serializeNulls()
		.create();
```

还有EventBus中也有一个Builder，只不过这个Builder外部访问不到而已，因为它的构造函数不是public的，但是你可以在EventBus这个类中看到他的应用。

```java
public static EventBusBuilder builder() {
	return new EventBusBuilder();
}
public EventBus() {
	this(DEFAULT_BUILDER);
}
EventBus(EventBusBuilder builder) {
	subscriptionsByEventType = new HashMap<Class<?>, CopyOnWriteArrayList<Subscription>>();
	typesBySubscriber = new HashMap<Object, List<Class<?>>>();
	stickyEvents = new ConcurrentHashMap<Class<?>, Object>();
	mainThreadPoster = new HandlerPoster(this, Looper.getMainLooper(), 10);
	backgroundPoster = new BackgroundPoster(this);
	asyncPoster = new AsyncPoster(this);
	subscriberMethodFinder = new SubscriberMethodFinder(builder.skipMethodVerificationForClasses);
	logSubscriberExceptions = builder.logSubscriberExceptions;
	logNoSubscriberMessages = builder.logNoSubscriberMessages;
	sendSubscriberExceptionEvent = builder.sendSubscriberExceptionEvent;
	sendNoSubscriberEvent = builder.sendNoSubscriberEvent;
	throwSubscriberException = builder.throwSubscriberException;
	eventInheritance = builder.eventInheritance;
	executorService = builder.executorService;
}
```

再看看著名的网络请求框架OkHttp


```java
Request.Builder builder=new Request.Builder();
Request request=builder.addHeader("","")
	.url("")
	.post(body)
	.build();
```

除了Request外，Response也是通过Builder模式创建的。贴一下Response的构造函数

```java
private Response(Builder builder) {
	this.request = builder.request;
	this.protocol = builder.protocol;
	this.code = builder.code;
	this.message = builder.message;
	this.handshake = builder.handshake;
	this.headers = builder.headers.build();
	this.body = builder.body;
	this.networkResponse = builder.networkResponse;
	this.cacheResponse = builder.cacheResponse;
	this.priorResponse = builder.priorResponse;
}
```

可见各大框架中大量的运用了Builder模式。最后总结一下

 - 定义一个静态内部类Builder，内部的成员变量和外部类一样
 - Builder类通过一系列的方法用于成员变量的赋值，并返回当前对象本身（this）
 - Builder类提供一个build方法或者create方法用于创建对应的外部类，该方法内部调用了外部类的一个私有构造函数，该构造函数的参数就是内部类Builder
 - 外部类提供一个私有构造函数供内部类调用，在该构造函数中完成成员变量的赋值，取值为Builder对象中对应的值

## 观察者模式


前面介绍了单例模式和Builder模式，这部分着重介绍一下观察者模式。先看下这个模式的定义。

>定义对象间的一种一对多的依赖关系，当一个对象的状态发送改变时，所有依赖于它的对象都能得到通知并被自动更新 

还是那句话，定义往往是抽象的，要深刻的理解定义，你需要自己动手实践一下。


先来讲几个情景。

 - 情景1
>有一种短信服务，比如天气预报服务，一旦你订阅该服务，你只需按月付费，付完费后，每天一旦有天气信息更新，它就会及时向你发送最新的天气信息。

 - 情景2
>杂志的订阅，你只需向邮局订阅杂志，缴纳一定的费用，当有新的杂志时，邮局会自动将杂志送至你预留的地址。

观察上面两个情景，有一个共同点，就是我们无需每时每刻关注我们感兴趣的东西，我们只需做的就是订阅感兴趣的事物，比如天气预报服务，杂志等，一旦我们订阅的事物发生变化，比如有新的天气预报信息，新的杂志等，被订阅的事物就会即时通知到订阅者，即我们。而这些被订阅的事物可以拥有多个订阅者，也就是一对多的关系。当然，严格意义上讲，这个一对多可以包含一对一，因为一对一是一对多的特例，没有特殊说明，本文的一对多包含了一对一。

现在你反过头来看看观察者模式的定义，你是不是豁然开朗了。

然后我们看一下观察者模式的几个重要组成。

 - 观察者，我们称它为Observer，有时候我们也称它为订阅者，即Subscriber
 - 被观察者，我们称它为Observable，即可以被观察的东西，有时候还会称之为主题，即Subject

至于观察者模式的具体实现，这里带带大家实现一下场景一，其实java中提供了**Observable**类和**Observer接口**供我们快速的实现该模式，但是为了加深印象，我们不使用这两个类。

场景1中我们感兴趣的事情是天气预报，于是，我们应该定义一个Weather实体类。

```java
public class Weather {
    private String description;

    public Weather(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    @Override
    public String toString() {
        return "Weather{" +
                "description='" + description + '\'' +
                '}';
    }
}

```



然后定义我们的被观察者，我们想要这个被观察者能够通用，将其定义成泛型。内部应该暴露register和unregister方法供观察者订阅和取消订阅，至于观察者的保存，直接用ArrayList即可，此外，当有主题内容发送改变时，会即时通知观察者做出反应，因此应该暴露一个notifyObservers方法，以上方法的具体实现见如下代码。

```java
public class Observable<T> {
    List<Observer<T>> mObservers = new ArrayList<Observer<T>>();

    public void register(Observer<T> observer) {
        if (observer == null) {
            throw new NullPointerException("observer == null");
        }
        synchronized (this) {
            if (!mObservers.contains(observer))
                mObservers.add(observer);
        }
    }

    public synchronized void unregister(Observer<T> observer) {
        mObservers.remove(observer);
    }

    public void notifyObservers(T data) {
        for (Observer<T> observer : mObservers) {
            observer.onUpdate(this, data);
        }
    }

}

```


而我们的观察者，只需要实现一个观察者的接口Observer，该接口也是泛型的。其定义如下。

```java
public interface Observer<T> {
    void onUpdate(Observable<T> observable,T data);
}

```

一旦订阅的主题发送变换就会回调该接口。

我们来使用一下，我们定义了一个天气变换的主题，也就是被观察者，还有两个观察者观察天气变换，一旦变换了，就打印出天气信息，注意一定要调用被观察者的register进行注册，否则会收不到变换信息。而一旦不敢兴趣了，直接调用unregister方法进行取消注册即可

```java
public class Main {
    public static void main(String [] args){
        Observable<Weather> observable=new Observable<Weather>();
        Observer<Weather> observer1=new Observer<Weather>() {
            @Override
            public void onUpdate(Observable<Weather> observable, Weather data) {
                System.out.println("观察者1："+data.toString());
            }
        };
        Observer<Weather> observer2=new Observer<Weather>() {
            @Override
            public void onUpdate(Observable<Weather> observable, Weather data) {
                System.out.println("观察者2："+data.toString());
            }
        };

        observable.register(observer1);
        observable.register(observer2);


        Weather weather=new Weather("晴转多云");
        observable.notifyObservers(weather);

        Weather weather1=new Weather("多云转阴");
        observable.notifyObservers(weather1);

        observable.unregister(observer1);

        Weather weather2=new Weather("台风");
        observable.notifyObservers(weather2);

    }
}

```

最后的输出结果也是没有什么问题的，如下
>观察者1：Weather{description='晴转多云'}
观察者2：Weather{description='晴转多云'}
观察者1：Weather{description='多云转阴'}
观察者2：Weather{description='多云转阴'}
观察者2：Weather{description='台风'}



接下来我们看看观察者模式在android中的应用。我们从最简单的开始。还记得我们为一个Button设置点击事件的代码吗。

```java
Button btn=new Button(this);
btn.setOnClickListener(new View.OnClickListener() {
	@Override
	public void onClick(View v) {
		Log.e("TAG","click");
	}
});
```

其实严格意义上讲，这个最多算是回调，但是我们可以将其看成是一对一的观察者模式，即只有一个观察者。

其实只要是set系列的设置监听器的方法最多都只能算回调，但是有一些监听器式add进去的，这种就是观察者模式了，比如RecyclerView中的addOnScrollListener方法

```java
private List<OnScrollListener> mScrollListeners;
public void addOnScrollListener(OnScrollListener listener) {
	if (mScrollListeners == null) {
		mScrollListeners = new ArrayList<OnScrollListener>();
	}
	mScrollListeners.add(listener);
}
public void removeOnScrollListener(OnScrollListener listener) {
	if (mScrollListeners != null) {
		mScrollListeners.remove(listener);
	}
}
public void clearOnScrollListeners() {
	if (mScrollListeners != null) {
		mScrollListeners.clear();
	}
}
```

然后有滚动事件时便会触发观察者进行方法回调

```java
public abstract static class OnScrollListener {
	public void onScrollStateChanged(RecyclerView recyclerView, int newState){}
	public void onScrolled(RecyclerView recyclerView, int dx, int dy){}
}

void dispatchOnScrolled(int hresult, int vresult) {
	//...
	if (mScrollListeners != null) {
		for (int i = mScrollListeners.size() - 1; i >= 0; i--) {
			mScrollListeners.get(i).onScrolled(this, hresult, vresult);
		}
	}
}
void dispatchOnScrollStateChanged(int state) {
	//...
	if (mScrollListeners != null) {
		for (int i = mScrollListeners.size() - 1; i >= 0; i--) {
			mScrollListeners.get(i).onScrollStateChanged(this, state);
		}
	}
}
```

类似的方法很多很多，都是add监听器系列的方法，这里也不再举例。


还有一个地方就是Android的广播机制，其本质也是观察者模式，这里为了简单方便，直接拿本地广播的代码说明，即LocalBroadcastManager。

我们平时使用本地广播主要就是下面四个方法
```java
LocalBroadcastManager localBroadcastManager=LocalBroadcastManager.getInstance(this);
localBroadcastManager.registerReceiver(BroadcastReceiver receiver, IntentFilter filter);
localBroadcastManager.unregisterReceiver(BroadcastReceiver receiver);
localBroadcastManager.sendBroadcast(Intent intent)
```
调用registerReceiver方法注册广播，调用unregisterReceiver方法取消注册，之后直接使用sendBroadcast发送广播，发送广播之后，注册的广播会收到对应的广播信息，这就是典型的观察者模式。具体的源代码这里也不贴。

android系统中的观察者模式还有很多很多，有兴趣的自己去挖掘，接下来我们看一下一些开源框架中的观察者模式。一说到开源框架，你首先想到的应该是EventBus。没错，EventBus也是基于观察者模式的。

观察者模式的三个典型方法它都具有，即注册，取消注册，发送事件

```java
EventBus.getDefault().register(Object subscriber);
EventBus.getDefault().unregister(Object subscriber);

EventBus.getDefault().post(Object event);
```

内部源码也不展开了。接下来看一下重量级的库，它就是RxJava，由于学习曲线的陡峭，这个库让很多人望而止步。

创建一个被观察者
```java
Observable<String> myObservable = Observable.create(  
    new Observable.OnSubscribe<String>() {  
        @Override  
        public void call(Subscriber<? super String> sub) {  
            sub.onNext("Hello, world!");  
            sub.onCompleted();  
        }  
    }  
);  
```

创建一个观察者，也就是订阅者

```java
Subscriber<String> mySubscriber = new Subscriber<String>() {  
    @Override  
    public void onNext(String s) { System.out.println(s); }  
  
    @Override  
    public void onCompleted() { }  
  
    @Override  
    public void onError(Throwable e) { }  
};  
```

观察者进行事件的订阅

```java
myObservable.subscribe(mySubscriber);  
```

具体源码也不展开，不过RxJava这个开源库的源码个人还是建议很值得去看一看的。

总之，在Android中观察者模式还是被用得很频繁的。

## 原型模式


这部分介绍的模式其实很简单，即原型模式，按照惯例，先看定义。

>用原型实例指定创建对象的种类，并通过拷贝这些原型创建新的对象。

这是什么鬼哦，本宝宝看不懂！不必过度在意这些定义，自己心里明白就ok了。没代码你说个jb。

首先我们定义一个Person类

```java
public class Person{
    private String name;
    private int age;
    private double height;
    private double weight;

    public Person(){
        
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        this.age = age;
    }

    public double getHeight() {
        return height;
    }

    public void setHeight(double height) {
        this.height = height;
    }

    public double getWeight() {
        return weight;
    }

    public void setWeight(double weight) {
        this.weight = weight;
    }

    @Override
    public String toString() {
        return "Person{" +
                "name='" + name + '\'' +
                ", age=" + age +
                ", height=" + height +
                ", weight=" + weight +
                '}';
    }
}
```

要实现原型模式，只需要按照下面的几个步骤去实现即可。

 - 实现Cloneable接口

```java
public class Person implements Cloneable{

}
```

 - 重写Object的clone方法

```java
@Override
public Object clone(){
	return null;
}
```

 - 实现clone方法中的拷贝逻辑

```java
@Override
public Object clone(){
	Person person=null;
	try {
		person=(Person)super.clone();
		person.name=this.name;
		person.weight=this.weight;
		person.height=this.height;
		person.age=this.age;
	} catch (CloneNotSupportedException e) {
		e.printStackTrace();
	}
	return person;
}
```

测试一下

```java
public class Main {
    public static void main(String [] args){
        Person p=new Person();
        p.setAge(18);
        p.setName("张三");
        p.setHeight(178);
        p.setWeight(65);
        System.out.println(p);

        Person p1= (Person) p.clone();
        System.out.println(p1);

        p1.setName("李四");
        System.out.println(p);
        System.out.println(p1);
    }
}

```


输出结果如下

>Person{name='张三', age=18, height=178.0, weight=65.0}
Person{name='张三', age=18, height=178.0, weight=65.0}
Person{name='张三', age=18, height=178.0, weight=65.0}
Person{name='李四', age=18, height=178.0, weight=65.0}

试想一下，两个不同的人，除了姓名不一样，其他三个属性都一样，用原型模式进行拷贝就会显得异常简单，这也是原型模式的应用场景之一。

>一个对象需要提供给其他对象访问，而且各个调用者可能都需要修改其值时，可以考虑使用原型模式拷贝多个对象供调用者使用，即保护性拷贝。

但是假设Person类里还有一个属性叫兴趣爱好，是一个List集合，就像这样子

```java
private ArrayList<String> hobbies=new ArrayList<String>();

public ArrayList<String> getHobbies() {
	return hobbies;
}

public void setHobbies(ArrayList<String> hobbies) {
	this.hobbies = hobbies;
}
```

在进行拷贝的时候要格外注意，如果你直接按之前的代码那样拷贝

```java
@Override
public Object clone(){
	Person person=null;
	try {
		person=(Person)super.clone();
		person.name=this.name;
		person.weight=this.weight;
		person.height=this.height;
		person.age=this.age;
		person.hobbies=this.hobbies;
	} catch (CloneNotSupportedException e) {
		e.printStackTrace();
	}
	return person;
}
```
会带来一个问题


使用测试代码进行测试

```java
public class Main {
    public static void main(String [] args){
        Person p=new Person();
        p.setAge(18);
        p.setName("张三");
        p.setHeight(178);
        p.setWeight(65);
        ArrayList <String> hobbies=new ArrayList<String>();
        hobbies.add("篮球");
        hobbies.add("编程");
        hobbies.add("长跑");
        p.setHobbies(hobbies);
        System.out.println(p);

        Person p1= (Person) p.clone();
        System.out.println(p1);

        p1.setName("李四");
        p1.getHobbies().add("游泳");
        System.out.println(p);
        System.out.println(p1);
    }
}

```

我们拷贝了一个对象，并添加了一个兴趣爱好进去，看下打印结果

>Person{name='张三', age=18, height=178.0, weight=65.0, hobbies=[篮球, 编程, 长跑]}
Person{name='张三', age=18, height=178.0, weight=65.0, hobbies=[篮球, 编程, 长跑]}
Person{name='张三', age=18, height=178.0, weight=65.0, hobbies=[篮球, 编程, 长跑, 游泳]}
Person{name='李四', age=18, height=178.0, weight=65.0, hobbies=[篮球, 编程, 长跑, 游泳]}

你会发现原来的对象的hobby也发生了变换。

其实导致这个问题的本质原因是我们只进行了浅拷贝，也就是只拷贝了引用，最终两个对象指向的引用是同一个，一个发生变化另一个也会发生变换，显然解决方法就是使用深拷贝。


```java
@Override
public Object clone(){
	Person person=null;
	try {
		person=(Person)super.clone();
		person.name=this.name;
		person.weight=this.weight;
		person.height=this.height;
		person.age=this.age;

		person.hobbies=(ArrayList<String>)this.hobbies.clone();
	} catch (CloneNotSupportedException e) {
		e.printStackTrace();
	}
	return person;
}
```

注意**person.hobbies=(ArrayList<String>)this.hobbies.clone();**，不再是直接引用而是进行了一份拷贝。再运行一下，就会发现原来的对象不会再发生变化了。

>Person{name='张三', age=18, height=178.0, weight=65.0, hobbies=[篮球, 编程, 长跑]}
Person{name='张三', age=18, height=178.0, weight=65.0, hobbies=[篮球, 编程, 长跑]}
Person{name='张三', age=18, height=178.0, weight=65.0, hobbies=[篮球, 编程, 长跑]}
Person{name='李四', age=18, height=178.0, weight=65.0, hobbies=[篮球, 编程, 长跑, 游泳]}

其实有时候我们会更多的看到原型模式的另一种写法。

 - 在clone函数里调用构造函数，构造函数的入参是该类对象。

```java
@Override
public Object clone(){
	return new Person(this);
}

```

 - 在构造函数中完成拷贝逻辑

```java
public Person(Person person){
	this.name=person.name;
	this.weight=person.weight;
	this.height=person.height;
	this.age=person.age;
	this.hobbies= new ArrayList<String>(hobbies);
}
```

其实都差不多，只是写法不一样。

现在来挖挖android中的原型模式。

先看Bundle类，该类实现了Cloneable接口

```java
public Object clone() {
	return new Bundle(this);
} 
public Bundle(Bundle b) {
	super(b);

	mHasFds = b.mHasFds;
	mFdsKnown = b.mFdsKnown;
}
```

然后是Intent类，该类也实现了Cloneable接口

```java
@Override
public Object clone() {
	return new Intent(this);
}
public Intent(Intent o) {
	this.mAction = o.mAction;
	this.mData = o.mData;
	this.mType = o.mType;
	this.mPackage = o.mPackage;
	this.mComponent = o.mComponent;
	this.mFlags = o.mFlags;
	this.mContentUserHint = o.mContentUserHint;
	if (o.mCategories != null) {
		this.mCategories = new ArraySet<String>(o.mCategories);
	}
	if (o.mExtras != null) {
		this.mExtras = new Bundle(o.mExtras);
	}
	if (o.mSourceBounds != null) {
		this.mSourceBounds = new Rect(o.mSourceBounds);
	}
	if (o.mSelector != null) {
		this.mSelector = new Intent(o.mSelector);
	}
	if (o.mClipData != null) {
		this.mClipData = new ClipData(o.mClipData);
	}
}
```

用法也显得十分简单，一旦我们要用的Intent与现有的一个Intent很多东西都是一样的，那我们就可以直接拷贝现有的Intent，再修改不同的地方，便可以直接使用。

```java
Uri uri = Uri.parse("smsto:10086");    
Intent shareIntent = new Intent(Intent.ACTION_SENDTO, uri);    
shareIntent.putExtra("sms_body", "hello");    

Intent intent = (Intent)shareIntent.clone() ;
startActivity(intent);
```

网络请求中一个最常见的开源库OkHttp中，也应用了原型模式。它就在**OkHttpClient**这个类中，它实现了Cloneable接口

```java
/** Returns a shallow copy of this OkHttpClient. */
@Override 
public OkHttpClient clone() {
	return new OkHttpClient(this);
}
private OkHttpClient(OkHttpClient okHttpClient) {
	this.routeDatabase = okHttpClient.routeDatabase;
	this.dispatcher = okHttpClient.dispatcher;
	this.proxy = okHttpClient.proxy;
	this.protocols = okHttpClient.protocols;
	this.connectionSpecs = okHttpClient.connectionSpecs;
	this.interceptors.addAll(okHttpClient.interceptors);
	this.networkInterceptors.addAll(okHttpClient.networkInterceptors);
	this.proxySelector = okHttpClient.proxySelector;
	this.cookieHandler = okHttpClient.cookieHandler;
	this.cache = okHttpClient.cache;
	this.internalCache = cache != null ? cache.internalCache : okHttpClient.internalCache;
	this.socketFactory = okHttpClient.socketFactory;
	this.sslSocketFactory = okHttpClient.sslSocketFactory;
	this.hostnameVerifier = okHttpClient.hostnameVerifier;
	this.certificatePinner = okHttpClient.certificatePinner;
	this.authenticator = okHttpClient.authenticator;
	this.connectionPool = okHttpClient.connectionPool;
	this.network = okHttpClient.network;
	this.followSslRedirects = okHttpClient.followSslRedirects;
	this.followRedirects = okHttpClient.followRedirects;
	this.retryOnConnectionFailure = okHttpClient.retryOnConnectionFailure;
	this.connectTimeout = okHttpClient.connectTimeout;
	this.readTimeout = okHttpClient.readTimeout;
	this.writeTimeout = okHttpClient.writeTimeout;
}
```

正如开头的注释**Returns a shallow copy of this OkHttpClient**，该clone方法返回了一个当前对象的浅拷贝对象。

至于其他框架中的原型模式，请读者自行发现。

## 策略模式



看下策略模式的定义

>策略模式定义了一些列的算法，并将每一个算法封装起来，而且使它们还可以相互替换。策略模式让算法独立于使用它的客户而独立变换。

乍一看，也没看出个所以然来。举个栗子吧。

假设我们要出去旅游，而去旅游出行的方式有很多，有步行，有坐火车，有坐飞机等等。而如果不使用任何模式，我们的代码可能就是这样子的。

```java
public class TravelStrategy {
	enum Strategy{
		WALK,PLANE,SUBWAY
	}
	private Strategy strategy;
	public TravelStrategy(Strategy strategy){
		this.strategy=strategy;
	}
	
	public void travel(){
		if(strategy==Strategy.WALK){
			print("walk");
		}else if(strategy==Strategy.PLANE){
			print("plane");
		}else if(strategy==Strategy.SUBWAY){
			print("subway");
		}
	}
	
	public void print(String str){
		System.out.println("出行旅游的方式为："+str);
	}
	
	public static void main(String[] args) {
		TravelStrategy walk=new TravelStrategy(Strategy.WALK);
		walk.travel();
		
		TravelStrategy plane=new TravelStrategy(Strategy.PLANE);
		plane.travel();
		
		TravelStrategy subway=new TravelStrategy(Strategy.SUBWAY);
		subway.travel();
	}
}

```


这样做有一个致命的缺点，一旦出行的方式要增加，我们就不得不增加新的else if语句，而这违反了面向对象的原则之一，对修改封闭。而这时候，策略模式则可以完美的解决这一切。

首先，需要定义一个策略接口。

```java

public interface Strategy {
	void travel();
}

```

然后根据不同的出行方式实行对应的接口

```java
public class WalkStrategy implements Strategy{

	@Override
	public void travel() {
		System.out.println("walk");
	}

}

```

```java
public class PlaneStrategy implements Strategy{

	@Override
	public void travel() {
		System.out.println("plane");
	}

}

```

```java
public class SubwayStrategy implements Strategy{

	@Override
	public void travel() {
		System.out.println("subway");
	}

}

```

此外还需要一个包装策略的类，并调用策略接口中的方法

```java
public class TravelContext {
	Strategy strategy;

	public Strategy getStrategy() {
		return strategy;
	}

	public void setStrategy(Strategy strategy) {
		this.strategy = strategy;
	}

	public void travel() {
		if (strategy != null) {
			strategy.travel();
		}
	}
}

```

测试一下代码

```java
public class Main {
	public static void main(String[] args) {
		TravelContext travelContext=new TravelContext();
		travelContext.setStrategy(new PlaneStrategy());
		travelContext.travel();
		travelContext.setStrategy(new WalkStrategy());
		travelContext.travel();
		travelContext.setStrategy(new SubwayStrategy());
		travelContext.travel();
	}
}

```

输出结果如下

>plane
walk
subway


可以看到，应用了策略模式后，如果我们想增加新的出行方式，完全不必要修改现有的类，我们只需要实现策略接口即可，这就是面向对象中的对扩展开放准则。假设现在我们增加了一种自行车出行的方式。只需新增一个类即可。

```java
public class BikeStrategy implements Strategy{

	@Override
	public void travel() {
		System.out.println("bike");
	}

}
```

之后设置策略即可

```java
public class Main {
	public static void main(String[] args) {
		TravelContext travelContext=new TravelContext();
		travelContext.setStrategy(new BikeStrategy());
		travelContext.travel();
	}
}
```

而在Android的系统源码中,策略模式也是应用的相当广泛的.最典型的就是属性动画中的应用.

我们知道,在属性动画中,有一个东西叫做插值器,它的作用就是根据时间流逝的百分比来来计算出当前属性值改变的百分比.

我们使用属性动画的时候,可以通过set方法对插值器进行设置.可以看到内部维持了一个时间插值器的引用，并设置了getter和setter方法，默认情况下是先加速后减速的插值器，set方法如果传入的是null，则是线性插值器。而时间插值器TimeInterpolator是个接口，有一个接口继承了该接口，就是Interpolator这个接口，其作用是为了保持兼容


```java
private static final TimeInterpolator sDefaultInterpolator =
		new AccelerateDecelerateInterpolator();  
private TimeInterpolator mInterpolator = sDefaultInterpolator; 
@Override
public void setInterpolator(TimeInterpolator value) {
	if (value != null) {
		mInterpolator = value;
	} else {
		mInterpolator = new LinearInterpolator();
	}
}

@Override
public TimeInterpolator getInterpolator() {
	return mInterpolator;
}

```


```java
public interface Interpolator extends TimeInterpolator {
    // A new interface, TimeInterpolator, was introduced for the new android.animation
    // package. This older Interpolator interface extends TimeInterpolator so that users of
    // the new Animator-based animations can use either the old Interpolator implementations or
    // new classes that implement TimeInterpolator directly.
}
```

此外还有一个BaseInterpolator插值器实现了Interpolator接口，并且是一个抽象类

```java
abstract public class BaseInterpolator implements Interpolator {
    private int mChangingConfiguration;
    /**
     * @hide
     */
    public int getChangingConfiguration() {
        return mChangingConfiguration;
    }

    /**
     * @hide
     */
    void setChangingConfiguration(int changingConfiguration) {
        mChangingConfiguration = changingConfiguration;
    }
}
```

平时我们使用的时候，通过设置不同的插值器，实现不同的动画速率变换效果，比如线性变换，回弹，自由落体等等。这些都是插值器接口的具体实现，也就是具体的插值器策略。我们略微来看几个策略。

```java
public class LinearInterpolator extends BaseInterpolator implements NativeInterpolatorFactory {

    public LinearInterpolator() {
    }

    public LinearInterpolator(Context context, AttributeSet attrs) {
    }

    public float getInterpolation(float input) {
        return input;
    }

    /** @hide */
    @Override
    public long createNativeInterpolator() {
        return NativeInterpolatorFactoryHelper.createLinearInterpolator();
    }
}

```


```java
public class AccelerateDecelerateInterpolator extends BaseInterpolator
        implements NativeInterpolatorFactory {
    public AccelerateDecelerateInterpolator() {
    }

    @SuppressWarnings({"UnusedDeclaration"})
    public AccelerateDecelerateInterpolator(Context context, AttributeSet attrs) {
    }

    public float getInterpolation(float input) {
        return (float)(Math.cos((input + 1) * Math.PI) / 2.0f) + 0.5f;
    }

    /** @hide */
    @Override
    public long createNativeInterpolator() {
        return NativeInterpolatorFactoryHelper.createAccelerateDecelerateInterpolator();
    }
}

```

内部使用的时候直接调用getInterpolation方法就可以返回对应的值了，也就是属性值改变的百分比。


属性动画中另外一个应用策略模式的地方就是估值器，它的作用是根据当前属性改变的百分比来计算改变后的属性值。该属性和插值器是类似的，有几个默认的实现。其中TypeEvaluator是一个接口。

```java
public interface TypeEvaluator<T> {

    public T evaluate(float fraction, T startValue, T endValue);

}

```



```java
public class IntEvaluator implements TypeEvaluator<Integer> {

    public Integer evaluate(float fraction, Integer startValue, Integer endValue) {
        int startInt = startValue;
        return (int)(startInt + fraction * (endValue - startInt));
    }
}
```


```java
public class FloatEvaluator implements TypeEvaluator<Number> {

    public Float evaluate(float fraction, Number startValue, Number endValue) {
        float startFloat = startValue.floatValue();
        return startFloat + fraction * (endValue.floatValue() - startFloat);
    }
}
```

```java
public class PointFEvaluator implements TypeEvaluator<PointF> {

    private PointF mPoint;


    public PointFEvaluator() {
    }

    public PointFEvaluator(PointF reuse) {
        mPoint = reuse;
    }

    @Override
    public PointF evaluate(float fraction, PointF startValue, PointF endValue) {
        float x = startValue.x + (fraction * (endValue.x - startValue.x));
        float y = startValue.y + (fraction * (endValue.y - startValue.y));

        if (mPoint != null) {
            mPoint.set(x, y);
            return mPoint;
        } else {
            return new PointF(x, y);
        }
    }
}

```

```java
public class ArgbEvaluator implements TypeEvaluator {
    private static final ArgbEvaluator sInstance = new ArgbEvaluator();

    public static ArgbEvaluator getInstance() {
        return sInstance;
    }

    public Object evaluate(float fraction, Object startValue, Object endValue) {
        int startInt = (Integer) startValue;
        int startA = (startInt >> 24) & 0xff;
        int startR = (startInt >> 16) & 0xff;
        int startG = (startInt >> 8) & 0xff;
        int startB = startInt & 0xff;

        int endInt = (Integer) endValue;
        int endA = (endInt >> 24) & 0xff;
        int endR = (endInt >> 16) & 0xff;
        int endG = (endInt >> 8) & 0xff;
        int endB = endInt & 0xff;

        return (int)((startA + (int)(fraction * (endA - startA))) << 24) |
                (int)((startR + (int)(fraction * (endR - startR))) << 16) |
                (int)((startG + (int)(fraction * (endG - startG))) << 8) |
                (int)((startB + (int)(fraction * (endB - startB))));
    }
}
```

上面的都是一些系统实现好的估值策略，在内部调用估值器的evaluate方法即可返回改变后的值了。我们也可以自定义估值策略。这里就不展开了。

当然，在开源框架中，策略模式也是无处不在的。

首先在Volley中，策略模式就能看到。

有一个重试策略接口

```java
public interface RetryPolicy {


    public int getCurrentTimeout();//获取当前请求用时（用于 Log）


    public int getCurrentRetryCount();//获取已经重试的次数（用于 Log）


    public void retry(VolleyError error) throws VolleyError;//确定是否重试，参数为这次异常的具体信息。在请求异常时此接口会被调用，可在此函数实现中抛出传入的异常表示停止重试。
}

```

在Volley中，该接口有一个默认的实现DefaultRetryPolicy，Volley 默认的重试策略实现类。主要通过在 retry(…) 函数中判断重试次数是否达到上限确定是否继续重试。

```java
public class DefaultRetryPolicy implements RetryPolicy {
	...
}

```

而策略的设置是在Request类中

```java

public abstract class Request<T> implements Comparable<Request<T>> {
    private RetryPolicy mRetryPolicy;
    public Request<?> setRetryPolicy(RetryPolicy retryPolicy) {
        mRetryPolicy = retryPolicy;
        return this;
    }
	public RetryPolicy getRetryPolicy() {
        return mRetryPolicy;
    }
}

```

此外，各大网络请求框架，或多或少都会使用到缓存，缓存一般会定义一个Cache接口，然后实现不同的缓存策略，如内存缓存，磁盘缓存等等，这个缓存的实现，其实也可以使用策略模式。直接看Volley，里面也有缓存。


定义了一个缓存接口

```java

/**
 * An interface for a cache keyed by a String with a byte array as data.
 */
public interface Cache {
    /**
     * Retrieves an entry from the cache.
     * @param key Cache key
     * @return An {@link Entry} or null in the event of a cache miss
     */
    public Entry get(String key);

    /**
     * Adds or replaces an entry to the cache.
     * @param key Cache key
     * @param entry Data to store and metadata for cache coherency, TTL, etc.
     */
    public void put(String key, Entry entry);

    /**
     * Performs any potentially long-running actions needed to initialize the cache;
     * will be called from a worker thread.
     */
    public void initialize();

    /**
     * Invalidates an entry in the cache.
     * @param key Cache key
     * @param fullExpire True to fully expire the entry, false to soft expire
     */
    public void invalidate(String key, boolean fullExpire);

    /**
     * Removes an entry from the cache.
     * @param key Cache key
     */
    public void remove(String key);

    /**
     * Empties the cache.
     */
    public void clear();

    /**
     * Data and metadata for an entry returned by the cache.
     */
    public static class Entry {
        /** The data returned from cache. */
        public byte[] data;

        /** ETag for cache coherency. */
        public String etag;

        /** Date of this response as reported by the server. */
        public long serverDate;

        /** The last modified date for the requested object. */
        public long lastModified;

        /** TTL for this record. */
        public long ttl;

        /** Soft TTL for this record. */
        public long softTtl;

        /** Immutable response headers as received from server; must be non-null. */
        public Map<String, String> responseHeaders = Collections.emptyMap();

        /** True if the entry is expired. */
        public boolean isExpired() {
            return this.ttl < System.currentTimeMillis();
        }

        /** True if a refresh is needed from the original data source. */
        public boolean refreshNeeded() {
            return this.softTtl < System.currentTimeMillis();
        }
    }

}

```

它有两个实现类**NoCache**和**DiskBasedCache**，使用的时候设置对应的缓存策略即可。


在android开发中，ViewPager是一个使用非常常见的控件，它的使用往往需要伴随一个Indicator指示器。**如果让你重新实现一个ViewPager，并且带有Indicator**，这时候，你会不会想到用策略模式呢？在你自己写的ViewPager中（不是系统的，当然你也可以继承系统的）持有一个策略接口Indicator的变量，通过set方法设置策略，然后ViewPager滑动的时候调用策略接口的对应方法改变指示器。默认提供几个Indicator接口的实现类，比如圆形指示器CircleIndicator、线性指示器LineIndicator、Tab指示器TabIndicator、图标指示器IconIndicator 等等等等。有兴趣的话自己去实现一个吧。
