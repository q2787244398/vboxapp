import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/node_service.dart';

/// Live TV page: channel list + play button.
class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  List<LiveSource> _liveSources = [];
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLiveSources();
  }

  Future<void> _loadLiveSources() async {
    final nodeService = context.read<NodeService>();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sources = await nodeService.getLiveSources();
      if (!mounted) return;
      setState(() {
        _liveSources = sources;
        _isLoading = false;
        if (sources.isEmpty) _error = '暂无直播源，请在配置中心添加';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _playSelected() {
    final source = _liveSources[_selectedIndex];
    final vod = Vod(
      id: source.name,
      name: source.name,
      playFrom: source.name,
      playUrl: source.url,
    );
    context.go('/player', extra: vod);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('直播'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLiveSources,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _liveSources.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.live_tv, size: 56, color: Colors.white24),
                      const SizedBox(height: 12),
                      Text(_error ?? '暂无直播源',
                          style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: _liveSources.length,
                        itemBuilder: (context, index) {
                          final source = _liveSources[index];
                          final isSelected = index == _selectedIndex;
                          return ListTile(
                            leading: source.logo != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      source.logo!,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(Icons.live_tv,
                                    size: 44, color: Colors.white54),
                            title: Text(source.name),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle,
                                    color: Color(0xFF58A6FF))
                                : const Icon(Icons.chevron_right,
                                    color: Colors.white38),
                            onTap: () => setState(
                                () => _selectedIndex = index),
                            onLongPress: () => _openSourceDetail(source),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _playSelected,
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text('播放「${_liveSources[_selectedIndex].name}」',
                                style: const TextStyle(fontSize: 15)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  void _openSourceDetail(LiveSource source) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(source.name),
        content: SelectableText(
          source.url,
          style: const TextStyle(
              fontSize: 12, fontFamily: 'monospace', height: 1.4),
        ),
      ),
    );
  }
}
