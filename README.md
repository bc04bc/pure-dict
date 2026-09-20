# Pure Dict · 纯净词典

<p align="center">
  <strong>一款现代、轻量、高颜值的离线英汉/汉英词典与智能背单词 Android 应用</strong>
  <br>
  <em>纯粹离线 · 语境纳词 · 智能复习 · 多端同步 · 零隐私追踪</em>
</p>

<p align="center">
  <a href="https://github.com/bc04bc/pure-dict/releases/latest">
    <img src="https://img.shields.io/github/v/release/bc04bc/pure-dict?color=blue&label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Platform-Android%20(ARM64)-3DDC84?logo=android" alt="Platform">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

## 💡 设计理念：让生词库真正贴合你的真实阅读环境

大多数背单词软件通常提供固定的预置词表（如四六级、托福、雅思、GRE 词汇书）。但学习者在实际英语使用中经常面临两大痛点：
1. **脱离语境，机械死记**：词汇书中的许多生僻义项在日常阅读中极少遇到，背了容易忘；
2. **缺乏个性化，与真实阅读脱节**：每个人已有的词汇背景各不相同，预置词表中充斥着大量自己已经掌握的词汇，或是难度跨度过大、近期根本读不到的超纲词。

**Pure Dict 的复习功能，旨在将背单词系统与使用者真实的阅读环境与词汇量背景深度结合**：

- **极度便捷的无感查询与自动纳词**：通过 Android 原生系统级划词查词（在任意浏览器、阅读器、聊天应用中长按文本即可直接查词）、通知栏快速查词、应用内即时搜索等方式，将查词门槛降到极低。
- **动态沉淀真实生词库**：用户在真实阅读场景中反复卡顿、主动查询过的词汇，才会自然汇入生词库；而单纯浏览衍生形态（如点击词形变换跳转）则不会污染复习词表。
- **要紧度算法（Urgency Algorithm）**：结合用户在阅读中的**查词频次**（遇过多次的词得分倍增）、**词典语料重要度标签**（核心高频词优先）以及**艾宾浩斯遗忘曲线**，动态量化每张卡片的复习紧迫度，把最宝贵的复习精力留给那些“在你的日常阅读中最高频出现、却尚未牢固掌握”的关键词。

---

## 🌟 核心特性

### 1. 📖 真实语境下的智能背单词系统
- **无感自动入库**：在日常查词中，生词自动纳入记忆池，告别繁琐的手动点星标、挑词书操作。
- **三维要紧度数学模型**：
  $$S_{\text{urgency}} = \Big(1.0 + \ln(1 + \text{查词次数})\Big) \times \text{语料重要度系数} \times \text{遗忘逾期倍率}$$
- **抽认翻转卡片（Flashcards）**：支持单手翻卡复习，提供「忘记了」、「模糊」、「记住了」三档记忆反馈，基于优化型间隔重复（SRS）动态递增复习间隔。
- **词形变换栈式探索**：单词详情页中名词复数、过去式、分词、比较级等词形变换为可点击 Chip，支持应用内栈式返回；浏览衍生形态时不纳词，保持复习词表纯粹。
- **自定义规划**：支持背单词总开关、每日复习上限配额（10 / 20 / 30 / 50 / 不限）。

### 2. ⚡ Android 原生长按划词查词 (`ACTION_PROCESS_TEXT`)
- **毫秒级极速弹窗**：在任何第三方 App（Chrome、微信、Telegram、电子书阅读器等）中长按选中文本，菜单点击「纯净词典」，即刻以半透明原生卡片弹窗查词。
- **免流氓权限**：底层直接直连私有 SQLite 检索，~10ms 极速响应，无需开启悬浮窗权限，无需常驻后台。
- **完美深浅色模式自适应**：全套高对比度 Material 3 语义色彩系统，浅色模式深咖啡黑文字清晰醒目，深色模式象牙白柔和舒适。
- **发音联动与无缝进阶**：弹窗内直接发音（跟随应用 TTS 配置），支持直接移出生词库，或一键跳转至主应用查看完整长篇释义。

### 3. ☁️ WebDAV 增量双向同步与离线冷备份
- **双向 LWW (Last-Write-Wins) 增量融合**：跨多台设备自动同步生词与记忆进度，绝不简单粗暴全量覆盖。
- **软删除与墓碑机制**：单词移出生词库后保留 30 天墓碑状态，同步至其他设备后自动传播删除，30 天后自动物理清理。
- **频次融合**：多端同时查词时，取最高频次并增量累计，确保学习数据不丢失。
- **开箱即用适配坚果云**：输入 `https://dav.jianguoyun.com/dav/` 时，应用自动规整并调用 `MKCOL` 在远端创建 `PureDict/` 备份文件夹，免除网页端建目录的烦恼。
- **极度省流与隐私可控**：单条单词数据仅约 230 字节，千词同步文件仅 ~0.2MB；支持启动时静默自动同步，支持一键导出/导入纯文本 JSON 离线冷备份。

### 4. 📚 全离线本地大词库与双向检索
- **纯离线内置词库**：内置 17 万词条精校 ECDICT 开源词库，无网状态下依然秒开秒查。
- **英汉 / 汉英双向搜索**：支持英文前缀联想检索与中文 bigram 倒排索引，搜中文释义也能即刻定位对应英文词汇。
- **详尽的释义与词族**：音标、词性分组释义、双解对照（可切换双解、纯中、纯英模式）、词形变换一应俱全。

### 5. 🔊 多引擎发音与音乐避让 (Audio Ducking)
- **四种发音来源**：
  - 微软 Edge 神经网络自然语音（音质最佳）
  - 有道词典真人原声（地道纯正，支持多端音频本地互通缓存）
  - 百度翻译发音
  - 设备系统本地离线 TTS（完全离线）
- **音乐避让功能**：听歌或听播客时查词发音，系统会自动短暂停留并降低背景音乐音量，发音结束后背景音立即恢复，不粗暴打断音乐播放。
- **离线音频缓存**：已播放的在线音频自动缓存至本地，节省流量，且支持在设置中一键查看与清理。

### 6. 🎨 现代 Material 3 视觉与通知栏查词
- **Material You 动态色彩**：Android 12+ 自动提取壁纸色系，自带专属「经典蓝」与「温暖奶油黄」精心调配的主题。
- **通知栏快速查词**：下拉状态栏即可在常驻通知中直接输入单词，查询结果直接展示在通知气泡中。
- **防误触保护**：清空生词库、清空历史、侧滑移出生词均设有二次确认弹窗。
- **绝对纯净**：无开屏广告、无弹窗推广、无后台隐私追踪、无不必要敏感权限。

---

## 📱 下载与安装

请前往 [GitHub Releases](https://github.com/bc04bc/pure-dict/releases/latest) 下载最新版本的 APK：

| 安装包类型 | 目标架构 | 体积 | 说明 |
| :--- | :--- | :--- | :--- |
| **`dict-1.1.0-arm64.apk`** | ARM64 (`arm64-v8a`) | **55.0 MB** | **推荐**。适用于近年的主流 Android 手机，体积深度精简 |

---

## 🛠️ 本地开发与构建

### 1. 环境要求
- Flutter SDK 3.12+ (Dart 3.x)
- Android SDK (minSdk 21, compileSdk 34+)
- Python 3（用于解压初始离线词库）

### 2. 准备词库与依赖
```bash
# 克隆仓库
git clone https://github.com/bc04bc/pure-dict.git
cd pure-dict

# 准备离线词库（解压 assets/dict.sqlite.gz）
python -c "import gzip,shutil; shutil.copyfileobj(gzip.open('assets/dict.sqlite.gz','rb'), open('assets/dict.sqlite','wb'))"

# 安装依赖
flutter pub get
```

### 3. 构建 ARM64 Release 安装包
```bash
flutter build apk --release --target-platform android-arm64
```
生成的 APK 文件将位于 `build/app/outputs/flutter-apk/app-release.apk`。

### 4. 运行自动化测试
```bash
flutter test
```

---

## 📂 项目架构

```
lib/
├── app/                  # 应用入口、路由 (GoRouter)、主题定义 (Material 3 / Cream)
├── core/
│   ├── db/               # 数据库服务 (离线 dict.sqlite / 用户 user.db)
│   ├── models/           # 数据模型 (WordEntry, UserWordEntry, StudyCardItem)
│   ├── network/          # 在线词典解析 fallback (有道等)
│   ├── study/            # 艾宾浩斯与要紧度数学算法 (UrgencyCalculator)
│   ├── sync/             # WebDAV 增量同步服务 (WebDavSyncService)
│   ├── text/             # 文本解析、词形变换分析、词频分级
│   └── tts/              # 多源 TTS 服务与音频避让引擎
└── features/
    ├── history/          # 浏览历史页面
    ├── home/             # 查词主页与即时联想
    ├── settings/         # 外观、发音、背单词限额、WebDAV 与备份设置
    ├── word/             # 单词详情页、词形变换 Chip、栈式回退
    └── wordbook/         # 背单词模块（今日复习翻卡 / 生词库概览）

android/
└── app/src/main/kotlin/com/example/dict/
    ├── MainActivity.kt               # Flutter 主引擎 Activity
    └── ProcessTextDialogActivity.kt  # 系统级划词查词原生弹窗 (零延迟直连 SQLite)
```

---

## 📄 数据来源与开源协议

- 离线英汉词库基于 [skywind3000/ECDICT](https://github.com/skywind3000/ECDICT) 开源项目（MIT License），在此深表感谢。
- 本项目遵循 [MIT License](LICENSE) 开源协议。

