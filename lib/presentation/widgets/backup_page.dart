/// 三形态共享视图：备份 / 还原页（B4）。
///
/// 功能对齐 `contract/docs/backup_v1.md`：
/// - 导出：勾选 9 个类目（网盘凭据默认不勾选）+ 可选口令 → `.vboxbak` 文件
/// - 还原：从备份目录选择 `.vboxbak` → 口令 → 类目 → 冲突策略（合并 / 覆盖）
///
/// 加解密与格式由 [BackupManager] 负责，采集 / 写回由 [BackupService] 负责，
/// 本文件只做交互编排。
library;

import 'package:flutter/material.dart';

import '../../data/datasources/local/backup_manager.dart';
import '../../data/datasources/local/backup_payload.dart';
import '../../data/datasources/local/backup_service.dart';

/// 备份 / 还原页。
class BackupPage extends StatefulWidget {
  /// 构造（[service] 便于测试注入）。
  const BackupPage({super.key, this.service});

  final BackupService? service;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final BackupService _service;

  /// 导出勾选状态（默认遵循契约 `defaultOn`）。
  final Map<BackupCategory, bool> _exportSelection =
      <BackupCategory, bool>{for (final BackupCategory c in BackupCategory.values) c: c.defaultOn};

  final TextEditingController _exportPassword = TextEditingController();

  bool _busy = false;
  List<BackupFileInfo> _files = const <BackupFileInfo>[];
  String? _fileError;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BackupService();
    _loadFiles();
  }

  @override
  void dispose() {
    _exportPassword.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    try {
      final List<BackupFileInfo> files = await _service.listBackupFiles();
      if (!mounted) return;
      setState(() {
        _files = files;
        _fileError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _fileError = '$e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── 导出 ────────────────────────────────────────────────

  Future<void> _export() async {
    final Set<BackupCategory> selected = _exportSelection.entries
        .where((MapEntry<BackupCategory, bool> e) => e.value)
        .map((MapEntry<BackupCategory, bool> e) => e.key)
        .toSet();
    if (selected.isEmpty) {
      _toast('请至少选择一个备份类目');
      return;
    }

    final String password = _exportPassword.text;
    setState(() => _busy = true);
    try {
      // 福利 3 键仅在加密备份时采集（契约 §7）。
      final BackupPayload payload = await _service.dump(
        categories: selected,
        includeWelfare: password.isNotEmpty,
      );
      final BackupEnvelope envelope = await BackupManager.instance.encrypt(
        plaintextJson: payload.encode(),
        meta: BackupService.buildMeta(),
        password: password.isEmpty ? null : password,
      );
      final String path =
          await _service.writeBackupFile(BackupManager.instance.encode(envelope));
      if (!mounted) return;
      _toast('已导出备份：$path');
      await _loadFiles();
    } catch (e) {
      if (!mounted) return;
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 还原 ────────────────────────────────────────────────

  Future<void> _restoreFlow(BackupFileInfo file) async {
    final _RestoreOptions? options = await showDialog<_RestoreOptions>(
      context: context,
      builder: (BuildContext context) => _RestoreDialog(file: file),
    );
    if (options == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final String content = await _service.readBackupFile(file.path);
      final BackupEnvelope envelope = BackupManager.instance.decode(content);
      final String plain = await BackupManager.instance.decrypt(
        envelope: envelope,
        password: options.password.isEmpty ? null : options.password,
      );
      final BackupPayload payload = BackupPayload.decode(plain);
      final BackupRestoreReport report = await _service.restore(
        payload: payload,
        categories: options.categories,
        strategy: options.strategy,
      );
      if (!mounted) return;
      final String missing =
          report.missing.isEmpty ? '' : '，跳过 ${report.missing.length} 个空类目';
      _toast('还原完成（${report.strategy.label}）：${report.total} 项$missing');
    } on BackupException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      _toast('还原失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteFile(BackupFileInfo file) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除备份'),
        content: Text('确定删除 ${file.name}？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.deleteBackupFile(file.path);
    await _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('备份与还原'),
          bottom: const TabBar(
            tabs: <Widget>[Tab(text: '导出备份'), Tab(text: '导入还原')],
          ),
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: <Widget>[_buildExport(), _buildRestore()],
              ),
      ),
    );
  }

  Widget _buildExport() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('备份类目', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final BackupCategory c in BackupCategory.values)
          CheckboxListTile(
            dense: true,
            value: _exportSelection[c],
            onChanged: (bool? v) =>
                setState(() => _exportSelection[c] = v ?? false),
            title: Text(c.label),
            subtitle: Text(c.subtitle),
            secondary: c.isSensitive
                ? Icon(Icons.lock_outline,
                    color: Theme.of(context).colorScheme.error)
                : null,
          ),
        const Divider(),
        TextField(
          controller: _exportPassword,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '备份口令（可选）',
            helperText: '留空则导出未加密备份；设置口令将同时包含福利设置',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.save_alt),
          label: const Text('导出备份'),
        ),
      ],
    );
  }

  Widget _buildRestore() {
    if (_fileError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('读取备份目录失败：$_fileError', textAlign: TextAlign.center),
        ),
      );
    }
    if (_files.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('暂无备份文件\n先在「导出备份」生成 .vboxbak 文件', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      itemCount: _files.length,
      separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final BackupFileInfo f = _files[index];
        return ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${_fmtSize(f.sizeBytes)} · ${_fmtTime(f.modifiedAt)}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: _busy ? null : () => _deleteFile(f),
          ),
          onTap: _busy ? null : () => _restoreFlow(f),
        );
      },
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

/// 还原对话框返回值。
class _RestoreOptions {
  const _RestoreOptions({
    required this.password,
    required this.strategy,
    required this.categories,
  });

  final String password;
  final ConflictStrategy strategy;
  final Set<BackupCategory> categories;
}

/// 还原参数对话框（口令 + 冲突策略 + 类目）。
class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.file});

  final BackupFileInfo file;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final TextEditingController _password = TextEditingController();
  ConflictStrategy _strategy = ConflictStrategy.merge;
  final Map<BackupCategory, bool> _selection =
      <BackupCategory, bool>{for (final BackupCategory c in BackupCategory.values) c: c.defaultOn};

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('还原备份'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(widget.file.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '备份口令',
                  helperText: '未加密备份可留空',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text('冲突策略', style: Theme.of(context).textTheme.titleSmall),
              _StrategyTile(
                label: '合并（保留本机，补齐备份）',
                selected: _strategy == ConflictStrategy.merge,
                onTap: () => setState(() => _strategy = ConflictStrategy.merge),
              ),
              _StrategyTile(
                label: '覆盖（清空本机后写入）',
                selected: _strategy == ConflictStrategy.overwrite,
                onTap: () =>
                    setState(() => _strategy = ConflictStrategy.overwrite),
              ),
              const Divider(),
              Text('还原类目', style: Theme.of(context).textTheme.titleSmall),
              for (final BackupCategory c in BackupCategory.values)
                CheckboxListTile(
                  dense: true,
                  value: _selection[c],
                  onChanged: (bool? v) =>
                      setState(() => _selection[c] = v ?? false),
                  title: Text(c.label),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final Set<BackupCategory> sel = _selection.entries
                .where((MapEntry<BackupCategory, bool> e) => e.value)
                .map((MapEntry<BackupCategory, bool> e) => e.key)
                .toSet();
            if (sel.isEmpty) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('请至少选择一个类目')));
              return;
            }
            Navigator.of(context).pop(_RestoreOptions(
              password: _password.text,
              strategy: _strategy,
              categories: sel,
            ));
          },
          child: const Text('开始还原'),
        ),
      ],
    );
  }
}

/// 单选样式（避免 `RadioListTile` 的 groupValue API 变更风险）。
class _StrategyTile extends StatelessWidget {
  const _StrategyTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(label),
      onTap: onTap,
    );
  }
}