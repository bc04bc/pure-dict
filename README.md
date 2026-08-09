# Pure Dict · 纯净词典

一款现代、美观的英汉/汉英离线词典 Android 应用，基于 Flutter 开发。

## 特性

- **离线词库**：内置 ECDICT 开源词库（17 万词条），无需网络即可查词
- **英汉 / 汉英双向**：输入中文也能搜索到相关英文词条
- **搜索联想**：英文前缀联想 + 中文 bigram 索引，实时响应
- **四种发音来源**：Edge 神经网络语音、本地离线 TTS、有道词典、百度翻译，可自由切换
- **单词详情**：音标、词性分组释义、词形变化、美/英发音、在线补充释义与例句
- **生词本与历史**：收藏生词、浏览记录，滑动删除
- **主题系统**：Material You 动态取色 / 经典蓝 / 温暖奶油黄，深浅色模式
- **通知栏查词**：在通知栏输入单词，结果直接以通知形式返回（无需打开应用）
- **快捷查词**（原生 RemoteInput）：长按选中文本即可查词

## 技术栈

- Flutter + Material 3
- Riverpod（状态管理）、go_router（路由）
- SQLite（sqflite）离线词库
- Edge TTS / flutter_tts / audioplayers（发音）
- dynamic_color（动态取色）

## 构建

```bash
# 1. 准备离线词库（需要 Python 3 + ECDICT 的 ecdict.csv）
#    从 https://github.com/skywind3000/ECDICT 下载 ecdict.csv 后：
python tools/build_dict.py /path/to/ecdict.csv assets/dict.sqlite

# 2. 构建 APK
flutter pub get
flutter build apk --release
```

APK 输出在 `build/app/outputs/flutter-apk/app-release.apk`。

## 项目结构

```
lib/
├── app/          # 应用入口、路由、主题
├── core/         # 数据层（词库、用户数据）、TTS 服务、网络
└── features/     # 页面：查词首页、详情、生词本、历史、设置、关于
tools/            # 词库构建脚本
```

## 数据来源

词库数据来自 [skywind3000/ECDICT](https://github.com/skywind3000/ECDICT)（MIT License），在此致谢。

## 开源许可

[MIT License](LICENSE)
