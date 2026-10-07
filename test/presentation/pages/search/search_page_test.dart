/// 表现层 widget 测试：搜索页（批次 D · D-02）。
///
/// 注入假 [ContentBrowseUseCases] + 内存 [SearchHistoryUseCases]，形态以
/// [UiFormController] 强制；无 IO、无原生依赖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vbox/core/utils/result.dart';
import 'package:vbox/domain/entities/douban/douban_models.dart';
import 'package:vbox/domain/entities/remote_source/remote_source.dart';
import 'package:vbox/domain/entities/spider/spider.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/presentation/pages/search/search_page.dart';
import 'package:vbox/presentation/ui_mode/ui_mode_resolver.dart';

import '../../../support/fakes.dart';

/// 假内容浏览用例：返回注入的站点 / 榜单 / 搜索结果，并记录搜索关键词。
class _FakeContentBrowseUseCases extends ContentBrowseUseCases {
  _FakeContentBrowseUseCases({
    this.sites = const <SiteConfig>[],
    this.results,
  }) : super(
          loadAllSources: () async =>
              const Success<AllSourcesContainer>(AllSourcesContainer()),
        );

  final List<SiteConfig> sites;
  final List<VodItem> Function(String keyword)? results;
  final List<String> searched = <String>[];

  @override
  Future<Result<List<SiteConfig>>> listSites() async =>
      Success<List<SiteConfig>>(sites);

  @override
  Future<Result<HomeContentResult>> homeContent(String siteKey) async =>
      const Success<HomeContentResult>(HomeContentResult(list: <VodItem>[]));

  @override
  Future<Result<SearchContentResult>> searchContent(
    String siteKey,
    String keyword, {
    int page = 1,
  }) async {
    searched.add(keyword);
    return Success<SearchContentResult>(
      SearchContentResult(page: page, list: results?.call(keyword)),
    );
  }
}

SiteConfig site(String key, String name) =>
    SiteConfig(key: key, name: name, type: 0, api: 'https://$key.example.com');

VodItem vod(String id, String name) =>
    VodItem(vodId: id, vodName: name, vodPic: '');

Widget _app(
  _FakeContentBrowseUseCases uc,
  SearchHistoryUseCases history, {
  UiFormOverride override = UiFormOverride.portrait,
  DoubanUseCases? douban,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UiFormController>.value(
        value: UiFormController(
          env: UiFormEnv(override: override, hasTouch: true),
        ),
      ),
      Provider<ContentBrowseUseCases>.value(value: uc),
      Provider<SearchHistoryUseCases>.value(value: history),
      Provider<DoubanUseCases>.value(
        value: douban ?? buildDoubanUseCases(),
      ),
    ],
    child: const MaterialApp(home: SearchPage()),
  );
}

void main() {
  testWidgets('空态：搜索历史 + 豆瓣榜单 + 全部站点', (WidgetTester tester) async {
    final _FakeContentBrowseUseCases uc = _FakeContentBrowseUseCases(
      sites: <SiteConfig>[site('s1', '站点1')],
    );
    final SearchHistoryUseCases history =
        SearchHistoryUseCases(InMemorySearchHistoryRepository(<String>['流浪地球', '三体']));

    await tester.pumpWidget(_app(
      uc,
      history,
      douban: buildDoubanUseCases(
        subjects: const <DoubanSubject>[
          DoubanSubject(id: 'd1', title: '豆瓣条目A', rating: 8.5),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('搜索历史'), findsOneWidget);
    expect(find.text('流浪地球'), findsOneWidget);
    expect(find.text('三体'), findsOneWidget);
    // 豆瓣栏目标签 + 数据（对齐 iOS `SearchView.doubanTabs`）
    expect(find.text('豆瓣周榜'), findsOneWidget);
    expect(find.text('豆瓣条目A'), findsOneWidget);
    // 全部站点区块（对齐 iOS「全部站点 (N)」）
    expect(find.textContaining('全部站点'), findsOneWidget);
    expect(find.text('站点1'), findsOneWidget);
  });

  testWidgets('提交搜索：进入结果态显示结果卡', (WidgetTester tester) async {
    final _FakeContentBrowseUseCases uc = _FakeContentBrowseUseCases(
      sites: <SiteConfig>[site('s1', '站点1')],
      results: (String kw) => <VodItem>[vod('r1', '搜索结果片')],
    );
    final SearchHistoryUseCases history =
        SearchHistoryUseCases(InMemorySearchHistoryRepository());

    await tester.pumpWidget(_app(uc, history));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(uc.searched, <String>['关键词']);
    expect(find.text('搜索结果片'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('清空历史：历史胶囊消失', (WidgetTester tester) async {
    final _FakeContentBrowseUseCases uc = _FakeContentBrowseUseCases(
      sites: <SiteConfig>[site('s1', '站点1')],
    );
    final InMemorySearchHistoryRepository repo =
        InMemorySearchHistoryRepository(<String>['流浪地球']);

    await tester.pumpWidget(_app(uc, SearchHistoryUseCases(repo)));
    await tester.pumpAndSettle();

    expect(find.text('流浪地球'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.text('流浪地球'), findsNothing);
    expect(repo.length, 0);
  });

  testWidgets('结果态切换源（竖屏 chips）：同关键词重搜', (WidgetTester tester) async {
    final _FakeContentBrowseUseCases uc = _FakeContentBrowseUseCases(
      sites: <SiteConfig>[site('s1', '站点1'), site('s2', '站点2')],
      results: (String kw) => <VodItem>[vod('r1', '结果$kw')],
    );
    final SearchHistoryUseCases history =
        SearchHistoryUseCases(InMemorySearchHistoryRepository());

    await tester.pumpWidget(_app(uc, history));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    // 全源并发搜索（对齐 iOS `searchStream`）：s1 + s2 各命中一次。
    expect(uc.searched, <String>['关键词', '关键词']);

    await tester.tap(find.text('站点2'));
    await tester.pumpAndSettle();

    // 切换源仍以同关键词全源重搜 → 累计 4 次（s1/s2 × 2 轮）。
    expect(uc.searched.length, 4);
    expect(find.text('结果关键词'), findsWidgets);
  });

  testWidgets('横屏结果态：左源列表 + 结果卡', (WidgetTester tester) async {
    final _FakeContentBrowseUseCases uc = _FakeContentBrowseUseCases(
      sites: <SiteConfig>[site('s1', '站点1'), site('s2', '站点2')],
      results: (String kw) => <VodItem>[vod('r1', '结果片')],
    );
    final SearchHistoryUseCases history =
        SearchHistoryUseCases(InMemorySearchHistoryRepository());

    await tester.pumpWidget(_app(
      uc,
      history,
      override: UiFormOverride.landscape,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.text('站点1'), findsOneWidget);
    expect(find.text('站点2'), findsOneWidget);
    // 全源并发：s1/s2 各回一条同名结果，`engineKey` 不同故均保留 → 两张卡。
    expect(find.text('结果片'), findsNWidgets(2));
  });
}