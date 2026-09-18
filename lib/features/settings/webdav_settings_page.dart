import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/webdav_sync_service.dart';

class WebDavSettingsPage extends ConsumerStatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  ConsumerState<WebDavSettingsPage> createState() =>
      _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends ConsumerState<WebDavSettingsPage> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _autoSync = false;
  int _lastSyncTime = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final service = await ref.read(webDavSyncServiceProvider.future);
    final config = service.getConfig();
    setState(() {
      _urlController.text = config.serverUrl;
      _usernameController.text = config.username;
      _passwordController.text = config.password;
      _autoSync = config.autoSyncOnLaunch;
      _lastSyncTime = config.lastSyncTime;
    });
  }

  Future<void> _saveConfig({bool updateController = false}) async {
    final service = await ref.read(webDavSyncServiceProvider.future);
    final normalized = WebDavSyncService.normalizeUrl(_urlController.text);
    if (updateController && _urlController.text.trim() != normalized) {
      _urlController.text = normalized;
    }
    await service.saveConfig(
      serverUrl: _urlController.text,
      username: _usernameController.text,
      password: _passwordController.text,
      autoSyncOnLaunch: _autoSync,
    );
  }

  Future<void> _testConnection() async {
    await _saveConfig(updateController: true);
    setState(() => _isLoading = true);

    final service = await ref.read(webDavSyncServiceProvider.future);
    final result = await service.testConnection();

    if (!mounted) return;
    setState(() => _isLoading = false);

    _showResultDialog(
      title: result.success ? '连接成功' : '连接失败',
      message: result.message,
      isSuccess: result.success,
    );
  }

  Future<void> _triggerSync() async {
    await _saveConfig(updateController: true);
    setState(() => _isLoading = true);

    final service = await ref.read(webDavSyncServiceProvider.future);
    final result = await service.sync();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _lastSyncTime = service.getConfig().lastSyncTime;
    });

    final details = result.success
        ? '同步成功！已上传 ${result.uploadedCount} 条，已下载并合并 ${result.downloadedCount} 条数据。'
        : result.message;

    _showResultDialog(
      title: result.success ? '增量同步完成' : '同步失败',
      message: details,
      isSuccess: result.success,
    );
  }

  Future<void> _exportBackup() async {
    final service = await ref.read(webDavSyncServiceProvider.future);
    final jsonStr = await service.exportBackupJson();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('数据备份 (JSON)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('已生成全量学习数据备份，你可以复制保存为 .json 文件离线留存。'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Text(
                  jsonStr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制备份数据到剪贴板'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('复制到剪贴板'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBackup() async {
    final restoreTextController = TextEditingController();
    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从 JSON 恢复数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请粘贴导出的 JSON 备份内容，系统将自动增量合并至本地。'),
            const SizedBox(height: 12),
            TextField(
              controller: restoreTextController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '在此粘贴备份 JSON 文本…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('执行合并恢复'),
          ),
        ],
      ),
    );

    if (shouldRestore == true && restoreTextController.text.trim().isNotEmpty) {
      try {
        final service = await ref.read(webDavSyncServiceProvider.future);
        final count =
            await service.restoreBackupJson(restoreTextController.text.trim());
        if (!mounted) return;
        _showResultDialog(
          title: '恢复成功',
          message: '已成功合并导入 $count 条生词记录。',
          isSuccess: true,
        );
      } catch (e) {
        if (!mounted) return;
        _showResultDialog(
          title: '恢复失败',
          message: 'JSON 格式解析错误或数据不匹配: $e',
          isSuccess: false,
        );
      }
    }
  }

  void _showResultDialog({
    required String title,
    required String message,
    required bool isSuccess,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: isSuccess ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int ms) {
    if (ms == 0) return '尚未同步';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV 同步与备份'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // Info banner
          Card(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.cloud_sync_rounded,
                      size: 24, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '多设备增量双向同步，自动合并生词与背单词学习进度。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Credentials card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '服务器配置',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // 1. WebDAV 地址
                  Text(
                    'WebDAV 地址',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: 'https://example.com/dav/',
                      prefixIcon: Icon(Icons.link_rounded, color: scheme.primary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: (_) => _saveConfig(),
                  ),
                  const SizedBox(height: 14),

                  // 2. 账号 / 用户名
                  Text(
                    '账号 / 用户名',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      hintText: '登录账号或邮箱',
                      prefixIcon:
                          Icon(Icons.person_outline_rounded, color: scheme.primary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                    ),
                    onChanged: (_) => _saveConfig(),
                  ),
                  const SizedBox(height: 14),

                  // 3. 应用密码 / Token
                  Text(
                    '应用密码 / Token',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: '网盘授权密码或 Token',
                      prefixIcon:
                          Icon(Icons.key_rounded, color: scheme.primary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    onChanged: (_) => _saveConfig(),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isLoading ? null : _testConnection,
                          icon: const Icon(Icons.wifi_find_rounded, size: 18),
                          label: const Text('测试连接'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isLoading ? null : _triggerSync,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.sync_rounded, size: 18),
                          label: const Text('立即同步'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Options & Sync status
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.autorenew_rounded),
                  title: const Text('应用启动时自动同步'),
                  subtitle: const Text('每次开启词典自动检测远端更新'),
                  value: _autoSync,
                  onChanged: (val) {
                    setState(() => _autoSync = val);
                    _saveConfig();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history_toggle_off_rounded),
                  title: const Text('上次同步时间'),
                  subtitle: Text(_formatTime(_lastSyncTime)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Cold Backup Card
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导出本地备份 (JSON)'),
                  subtitle: const Text('将生词本与背单词记录导出为纯文本离线备份'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _exportBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('从 JSON 恢复数据'),
                  subtitle: const Text('粘贴备份内容，合并恢复生词记录'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _restoreBackup,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
