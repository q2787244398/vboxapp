import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/database_service.dart';
import '../services/node_service.dart';
import 'video_grid.dart';

/// Search page with keyword search and history chips.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Vod> _results = [];
  List<SearchHistory> _history = [];
  bool _isSearching = false;
  String? _activeSite;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final db = context.read<DatabaseService>();
    final history = await db.getSearchHistory(limit: 20);
    if (mounted) {
      setState(() => _history = history);
    }
  }

  Future<void> _performSearch(String keyword) async {
    final text = keyword.trim();
    if (text.isEmpty) return;

    final nodeService = context.read<NodeService>();
    final db = context.read<DatabaseService>();

    setState(() => _isSearching = true);

    final results =
        await nodeService.searchVideos(text, siteKey: _activeSite);
    await db.addSearchHistory(text);

    if (!mounted) return;
    setState(() {
      _results = results;
      _isSearching = false;
    });
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('搜索历史'),
                  content: _history.isEmpty
                      ? const Text('暂无历史记录')
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final item in _history)
                              ListTile(
                                leading: const Icon(Icons.search, size: 20),
                                title: Text(item.keyword,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                trailing: Text('${item.count} 次',
                                    style: const TextStyle(
                                        color: Colors.white38)),
                                onTap: () {
                                  Navigator.pop(context);
                                  _searchCtrl.text = item.keyword;
                                  _performSearch(item.keyword);
                                },
                              ),
                          ],
                        ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        final db = context.read<DatabaseService>();
                        await db.clearSearchHistory();
                        _loadHistory();
                        Navigator.pop(context);
                      },
                      child: const Text('清空'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onSubmitted: _performSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '搜索电影、剧集、综艺…',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _performSearch(_searchCtrl.text),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // History chips
          if (_history.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final item in _history)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(item.keyword),
                        onPressed: () {
                          _searchCtrl.text = item.keyword;
                          _performSearch(item.keyword);
                        },
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _results.isNotEmpty
                    ? VideoGrid(
                        videos: _results,
                        onVideoTap: (vod) => context.go(
                          '/detail/${vod.siteKey ?? _activeSite ?? ''}/${vod.id}',
                          extra: vod,
                        ),
                      )
                    : Center(
                        child: _history.isNotEmpty
                            ? const Text('没有更多结果',
                                style: TextStyle(color: Colors.white54))
                            : const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 48, color: Colors.white24),
                                  SizedBox(height: 12),
                                  Text('输入关键词开始搜索',
                                      style: TextStyle(color: Colors.white54)),
                                ],
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
