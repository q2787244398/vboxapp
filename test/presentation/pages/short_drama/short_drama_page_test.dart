/// 表现层 widget 测试：短剧页（批次 D · D-04）。
///
/// 注入假 [ContentBrowseUseCases]（子类覆盖 listSites / categories /
/// categoryContent / searchContent），形态以 [UiFormController] 强制；
/// 无 IO、无原生依赖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vbox/core/utils/result.dart';
import 'package:vbox/domain/entities/remote_source/remote_source.dart';
import 'package:vbox/domain/entities/spider/spider.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/pages/short_drama/short_drama_page.dart';
import 'package:vbox/presentation/ui_mode/ui_mode_resolver.dart';

/// 假内容浏览用例：返回注入的站点 / 各站分类 / 分类内容 / 搜索结果。
class _FakeContentBrowseUseCases extends ContentBrowseUseCases {
  _FakeContentBrowseUseCases({
    this.sites = const <SiteConfig>[],
    this.categoriesBySite = const <String, List<VodCategory>>{},
    this.videos,
    this.searchResults = const <VodItem>[],
  }) : super(
          loadAllSources: () async =>
              const Success<AllSourcesContainer>(AllSourcesContainer()),
        );

  final List<SiteConfig> sites;
  final Map<String, List<VodCategory>> categoriesBySite;
  final List<VodItem> Function(String siteKey, String? tid, int page)? videos;
  final List<VodItem> searchResults;

  @override
  Future<Result<List<SiteConfig>>> listSites() async =>
      Success<List<SiteConfig>>(sites);

  @override
  Future<Result<List<VodCategory>>> categories(String siteKey) async =>
      Success<List<VodCategory>>(
        categoriesBySite[siteKey] ?? const <VodCategory>[],
      );

  @override
  Future<Result<CategoryContentResult>> categoryContent(
    String siteKey, {
    String? tid,
    int page = 1,
  }) async {
    return Success<CategoryContentResult>(
      CategoryContentResult(
        page: page,
        pagecount: 1,
        list: videos?.call(siteKey, tid, page) ?? const <VodItem>[],
      ),
    );
  }

  @override
  Future<Result<SearchContentResult>> searchContent(
    String siteKey,
    String keyword, {
    int page = 1,
  }) async {
    return Success<SearchContentResult>(
      SearchContentResult(page: page, list: searchResults),
    );
  }
}

SiteConfig site(String key, String name) =>
    SiteConfig(key: key, name: name, type: 0, api: 'https://$key.example.com');

VodCategory cat(String id, String name) =>
    VodCategory(typeId: id, typeName: name);

VodItem vod(String id, String name) =>
    VodItem(vodId: id, vodName: name, vodPic: '');

Widget _app(_FakeContentBrowseUseCases uc) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UiFormController>.value(
        value: UiFormController(
          env: const UiFormEnv(
            override: UiFormOverride.portrait,
            hasTouch: true,
          ),
        ),
      ),
      Provider<ContentBrowseUseCases>.value(value: uc),
    ],
    child: const MaterialApp(home: ShortDramaPage()),
  );
}

void main() {
  testWidgets('无站点：显示扫描失败提示', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_FakeContentBrowseUseCases()));
    await tester.pumpAndSettle();

    expect(find.textContaining('无可用站点'), findsOneWidget);
  });

  testWidgets('扫到短剧分类：源标签 + 内容网格', (WidgetTester tester) async {
    final _FakeContentBrowseUseCases uc = _FakeContentBrowseUseCases(
      sites: <SiteConfig>[site('s1', '站点1')],
      categoriesBySite: <String, List<VodCategory>>{
        's1': <VodCategory>[cat('1', '短剧')],
      },
      videos: (_, __, ___) => <VodItem>[vod('1', '短剧片')],
    );
    await tester.pumpWidget(_app(uc));
    await tester.pumpAndSettle();

    expect(find.text('站点1(短剧)'), findsOneWidget);
    expect(find.text('短剧片'), findsOneWidget);
  });

  testWidgets('切换源标签：重载该源内容', (WidgetTester tester) async {
    final _FakeContentBrowseUseCases uc = _FakeContentBrowseUseCases(
      sites: <SiteConfig>[site('s1', '站点1'), site('s2', '站点2')],
      categoriesBySite: <String, List<VodCategory>>{
        's1': <VodCategory>[cat('1', '短剧')],
        's2': <VodCategory>[cat('2', '剧场')],
      },
      videos: (String siteKey, _, __) {
        if (siteKey == 's2') return <VodItem>[vod('2', '剧场片')];
        return <VodItem>[vod('1', '短剧片')];
      },
    );
    await tester.pumpWidget(_app(uc));
    await tester.pumpAndSettle();

    expect(find.text('短剧片'), findsOneWidget);

    await tester.tap(find.text('站点2(剧场)'));
    await tester.pumpAndSettle();

    expect(find.text('剧场片'), findsOneWidget);
    expect(find.text('短剧片'), findsNothing);
  });

  testWidgets('搜索：提交关键词显示结果', (WidgetTester tester) async {
    final _FakeContentBrowseUseCases uc = _FakeContentBrowseUseCases(
      sites: <SiteConfig>[site('s1', '站点1')],
      categoriesBySite: <String, List<VodCategory>>{
        's1': <VodCategory>[cat('1', '短剧')],
      },
      videos: (_, __, ___) => <VodItem>[vod('1', '短剧片')],
      searchResults: <VodItem>[vod('9', '目标结果')],
    );
    await tester.pumpWidget(_app(uc));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '搜索片');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('目标结果'), findsOneWidget);
  });
}