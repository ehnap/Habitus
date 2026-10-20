# Habitus

Habitus 是一个 Navidrome 客户端。同一套 Flutter 代码面向 Android、iOS、Windows 和 macOS。它通过 Subsonic / OpenSubsonic 连接你自己的 Navidrome，一次只使用一个音乐库，可以在多个库之间切换。

界面是简体中文。播放使用系统播放器（Android ExoPlayer、Apple AVPlayer、Windows Media Foundation），不内置 ffmpeg。Linux 可以编译运行界面，但没有系统播放后端，也不在验收范围内。

## 本地运行

需要 Flutter 3.13 或更新的稳定版。

```bash
flutter pub get
flutter run -d android
flutter run -d ios
flutter run -d windows
flutter run -d macos
flutter run -d linux
```

打开应用后，在「我的」或空的首页里添加音乐库：填写地址、用户名和密码。HTTP 地址会先提示明文风险。自签证书需要勾选信任当前证书。

## 测试

```bash
flutter test
```

## 平台说明

- Android 最低 8.0（API 26）。允许明文 HTTP，并使用媒体通知。
- iOS 最低 16，开启后台音频。
- macOS 最低 12，沙盒允许访问网络和本机回环代理。
- Windows 使用系统 Media Foundation。
- 播放页可以在封面和滚动歌词之间切换。Windows 和 macOS 还可以打开一小块置顶、可拖动的桌面歌词，或把主窗口收成迷你条。关掉桌面歌词不会退出应用。迷你条保持置顶，恢复时回到原来的大小和位置。同一套窗口代码在 Linux 上也会编译进去。
- 「我的」里可以填一个 LrcApi 地址（`GET /lyrics`）。留空则不请求。只有 Navidrome 没有这首歌的歌词时才会用它。地址只存在本机设置里，不会写进日志。
- 密码只放在系统安全存储里。安全存储不可用时，不会把密码写进数据库。
