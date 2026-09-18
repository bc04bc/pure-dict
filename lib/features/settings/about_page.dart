import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _repoUrl = 'https://github.com/bc04bc/pure-dict';

  static const _licenses = [
    ('ECDICT 词库', 'MIT License', 'skywind3000',
        '免费英汉词典数据库，本项目离线词库数据来源'),
    ('flutter_riverpod', 'MIT License', 'Riverpod',
        '声明式状态管理框架'),
    ('go_router', 'BSD-3-Clause', 'Flutter 团队',
        '声明式路由与导航'),
    ('sqflite', 'BSD-2-Clause', 'tekartik',
        'SQLite 数据库插件'),
    ('dynamic_color', 'BSD-3-Clause', 'Flutter 团队',
        'Material You 动态取色'),
    ('audioplayers', 'MIT License', 'luanpotter',
        '音频播放'),
    ('edge_tts', 'MIT License', 'edge-tts 社区',
        '微软 Edge 神经网络语音合成'),
    ('flutter_tts', 'MIT License', 'Dennis Kwong',
        '本地离线语音合成（TTS）'),
    ('http', 'BSD-3-Clause', 'Dart 团队',
        'HTTP 客户端'),
    ('path_provider', 'BSD-3-Clause', 'Flutter 团队',
        '获取应用文件目录'),
    ('shared_preferences', 'BSD-3-Clause', 'Flutter 团队',
        '轻量键值持久化'),
    ('path', 'BSD-3-Clause', 'Dart 团队',
        '路径处理工具'),
    ('cupertino_icons', 'MIT License', 'Flutter 团队',
        'iOS 风格图标'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '关于',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                size: 48,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '词典',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'v1.1.0',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '现代英汉 / 汉英离线词典\n英英释义由 AI 翻译为中文（双解对照）',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.code_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              title: const Text(
                'GitHub 仓库',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('pure-dict · 开源项目主页'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => launchUrl(
                Uri.parse(_repoUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '引用项目',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '本项目参考并使用了以下开源项目，感谢所有贡献者：',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final (name, license, author, desc) in _licenses)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ExpansionTile(
                shape: const RoundedRectangleBorder(),
                collapsedShape: const RoundedRectangleBorder(),
                leading: Icon(
                  Icons.code_rounded,
                  size: 22,
                  color: scheme.primary,
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('$license · $author'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        desc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '数据来源：ECDICT 开源词库（MIT License）',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
