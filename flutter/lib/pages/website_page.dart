import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/node_service.dart';
import 'video_grid.dart';

/// Website page: browse spider sites and their home feeds.
class WebsitePage extends StatefulWidget {
  const WebsitePage({super.key});

  @override
  State<WebsitePage> createState() => _WebsitePageState();
}

class _WebsitePageState extends State<WebsitePage> {
  List<VodSite> _sites = [];
  List<Vod> _videos = [];
  bool _isLoading = true;
  String? _selectedSiteKey;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final nodeService = context.read<NodeService>();

    try {
      final sites = await nodeService.getSites();
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _isLoading = false;
      });

      if (sites.isNotEmpty) {
        _loadSiteHome(sites.first.key);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSiteHome(String siteKey) async {
    final nodeService = context.read<NodeService>();
    try {
      final videos = await nodeService.getHomeVideos(siteKey: siteKey);
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _selectedSiteKey = siteKey;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网站'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                _selectedSiteKey != null ? _loadSiteHome(_selectedSiteKey!) : _loadData(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Site selector
                if (_sites.isNotEmpty)
                  SizedBox(
                    height: 52,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _sites.length,
                      itemBuilder: (context, index) {
                        final site = _sites[index];
                        final isSelected = site.key == _selectedSiteKey;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: isSelected,
                            label: Text(site.name),
                            onSelected: (_) => _loadSiteHome(site.key),
                          ),
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: _videos.isNotEmpty
                      ? VideoGrid(
                          videos: _videos,
                          onVideoTap: (vod) => context.go(
                            '/detail/${vod.siteKey ?? _selectedSiteKey ?? ''}/${vod.id}',
                            extra: vod,
                          ),
                        )
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.language, size: 48, color: Colors.white24),
                              SizedBox(height: 12),
                              Text('暂无内容，请先在配置中心添加站点',
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
