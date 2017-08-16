title: 再谈brew
date: 2017-08-16 16:29:01
categories: [Mac]
tags: [Mac, brew]
---

用brew一直都是傻乎乎的brew install来安装某个软件，直到有一天，需要安装一个低版本的软件，发现自己不会，于是再谈谈这东西。

<!-- more -->

安装brew

```
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

升级brew自身

```
brew update
```

查看brew自身的一些信息

```
brew config
```

安装某个软件

```
brew install [FORMULA...]
```

卸载某个软件

```
brew uninstall FORMULA...
```

升级某个软件

```
brew upgrade [FORMULA...]
```

查看某个软件的安装详情

```
brew info [FORMULA...]
```

打开某个软件的主页

```
brew home [FORMULA...]
```

查看某个软件的安装选项

```
brew options [FORMULA...]
```

列出某个软件安装的所有信息

```
brew list [FORMULA...]
```

搜索某个软件

```
brew search [TEXT|/REGEX/]
```

如

```
brew search automake
```

使用rb文件来安装，支持远程文件或本地文件

如

```
brew install https://raw.githubusercontent.com/Homebrew/homebrew-core/487047e550fa24bc0486c0f0243da837ddaa488c/Formula/cmake.rb
```

也可以使用本地文件

```
brew install cmake.rb
```

安装特定版本的软件

方法一：

首先找到github上的rb文件，找到对应版本的raw文件，如https://raw.githubusercontent.com/Homebrew/homebrew-core/487047e550fa24bc0486c0f0243da837ddaa488c/Formula/cmake.rb，然后执行如下命令来安装

```
brew install 远程地址
```

方法二：

如果找不到对应版本，可以将最新的rb文件下载到本地，修改url和sha256值为你需要的版本对应的值，然后执行如下命令来安装

```
brew install 文件路径
```

mac上sha256的值可以使用如下命令计算

```
shasum -a 256 文件路径
```

去除链接

```
brew unlink formula
```

链接

```
brew link [FORMULA...]
```

切换版本

```
brew switch <name> <version>
```