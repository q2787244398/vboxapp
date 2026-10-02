/// 领域层单测：ContentBrowseUseCases（站点列表 / 首页 / 分类 / 搜索）。
///
/// 引擎路径注入 FakeSpiderEngineFactory；CMS 路径注入 MockClient（真实
/// CmsV10Datasource）；无 IO、无原生依赖。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vbox/core/errors/failures.dart';
import 'package:vbox/core/network/http_client.dart';
import 'package:vbox/core/utils/result.dart';
import 'package:vbox/data/datasources/remote/remote.dart';
import 'package:vbox/domain/entities/remote_source/remote_source.dart';
import 'package:vbox/domain/entities/spider/spider.dart';
import 'package:vbox/domain/usecases/usecases.dart';
import 'package:vbox/platform/runtime/jsc_ffi.dart';
import 'package:vbox/platform/runtime/quickjs_ffi.dart';
import 'package:vbox/platform/spider/node_http_client.dart';
import 'package:vbox/platform/spider/spider_engine_factory.dart';

// ─────────────── 测试替身 ───────────────

class _FakeSpiderEngine implements SpiderEngine {
  _FakeSpiderEngine(this.engineType,
      {this.homeResult, this.categoryResult, this.searchResult});

  @override
  SpiderEngineType engineType;
  HomeContentResult? homeResult;
  CategoryContentResult? categoryResult;
  SearchContentResult? searchResult;
  final List<String> calls = <String>[];
  String? loadedUrl;
  bool ready = true;

  @override
  set onLog(void Function(String)? handler) {}

  @override
  Future<void> loadScript(String script) async => calls.add('loadScript');

  @override
  Future<void> loadLibrary(String script) async => calls.add('loadLibrary');

  @override
  Future<void> loadScriptFromURL(String urlString) async {
    calls.add('loadScriptFromURL');
    loadedUrl = urlString;
  }

  @override
  Future<void> registerSpider() async => calls.add('registerSpider');

  @override
  bool get isSpiderReady => ready;

  @override
  Future<HomeContentResult> callHomeContent() async {
    calls.add('homeContent');
    return homeResult ?? const HomeContentResult();
  }

  @override
  Future<SearchContentResult> callSearchContent(String keyword, int pg) async {
    calls.add('searchContent:$keyword:$pg');
    return searchResult ?? const SearchContentResult();
  }

  @override
  Future<CategoryContentResult> callCategoryContent(
          String tid, int pg, String extend) async {
    calls.add('categoryContent:$tid:$pg');
    return categoryResult ?? const CategoryContentResult();
  }

  @override
  Future<DetailContentResult> callDetailContent(String ids) async =>
      const DetailContentResult();

  @override
  Future<PlayerContentResult> callPlayerContent(
          String vodId, String flag, String url) async =>
      PlayerContentResult();

  @override
  Future<void> dispose() async => calls.add('dispose');
}

class _FakeSpiderEngineFactory extends SpiderEngineFactory {
  _FakeSpiderEngineFactory(this.engine);

  final _FakeSpiderEngine engine;
  final List<SpiderEngineType> createdTypes = <SpiderEngineType>[];

  @override
  SpiderEngine create(
    SpiderEngineType type, {
    NodeHttpClient? nodeClient,
    QuickJsNativeBridge? quickJsBridge,
    JsCoreNativeBridge? jsCoreBridge,
    String? siteKey,
    String? baseUrl,
    String? requestId,
    void Function(String)? onLog,
  }) {
    createdTypes.add(type);
    return engine;
  }
}

AllSourcesContainer buildContainer(List<Map<String, Object?>> sites) =>
    AllSourcesContainer.fromJson(<String, Object?>{
      'apiSources': <String, Object?>{
        'sites': sites
            .where((Map<String, Object?> s) => ((s['type'] as num?) ?? 0) < 3)
            .toList(),
      },
      'spiderSources': <String, Object?>{
        'sites': sites
            .where((Map<String, Object?> s) => ((s['type'] as num?) ?? 0) == 3)
            .toList(),
      },
    });

Map<String, Object?> siteJson({
  required String key,
  int type = 3,
  String? api,
}) =>
    <String, Object?>{
      'key': key,
      'name': key,
      'type': type,
      if (api != null) 'api': api,
    };

/// 组装 CMS MockClient：按 `ac` 分流返回分类/列表。
HttpClient cmsClient({List<Map<String, Object?>> classes = const [], List<Map<String, Object?>> list = const []}) {
  return HttpClient(
    inner: MockClient((http.Request req) async {
      final String ac = req.url.queryParameters['ac'] ?? '';
      Map<String, Object?> body;
      if (ac == 'list') {
        body = <String, Object?>{'class': classes};
      } else if (ac == 'videolist') {
        body = <String, Object?>{'list': list};
      } else {
        body = <String, Object?>{};
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    }),
    retryBaseDelay: Duration.zero,
  );
}

void main() {
  group('listSites', () {
    test('空站点 → UnknownFailure', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[]),
        ),
      );
      final Result<List<SiteConfig>> r = await uc.listSites();
      expect(r.failureOrNull, isA<UnknownFailure>());
    });

    test('返回解析后的站点（含 key）', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'a', type: 0, api: 'https://a.com'),
            siteJson(key: 'b', type: 3, api: 'https://b.com/x.js'),
          ]),
        ),
      );
      final Result<List<SiteConfig>> r = await uc.listSites();
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(r.valueOrNull!.map((SiteConfig s) => s.key), <String>['a', 'b']);
    });
  });

  group('homeContent', () {
    test('空 siteKey → ValidationFailure', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => const Success<AllSourcesContainer>(
          AllSourcesContainer(),
        ),
      );
      expect(
        (await uc.homeContent('  ')).failureOrNull,
        isA<ValidationFailure>(),
      );
    });

    test('allSources 失败 → 透传 Failure', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async =>
            const Err<AllSourcesContainer>(NetworkFailure('断网')),
      );
      expect(
        (await uc.homeContent('k')).failureOrNull,
        isA<NetworkFailure>(),
      );
    });

    test('未找到站点 → ValidationFailure', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[siteJson(key: 'other')]),
        ),
      );
      expect(
        (await uc.homeContent('missing')).failureOrNull,
        isA<ValidationFailure>(),
      );
    });

    test('.jar 站点 → UnsupportedFailure', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'j', type: 3, api: 'http://x/a.jar'),
          ]),
        ),
      );
      expect(
        (await uc.homeContent('j')).failureOrNull,
        isA<UnsupportedFailure>(),
      );
    });

    test('CMS 路径：分类 + 列表合并返回', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'cms', type: 0, api: 'https://cms.example.com'),
          ]),
        ),
        cmsDatasource: CmsV10Datasource(
          client: cmsClient(
            classes: <Map<String, Object?>>[
              <String, Object?>{'type_id': '1', 'type_name': '电影'},
            ],
            list: <Map<String, Object?>>[
              <String, Object?>{
                'vod_id': '1',
                'vod_name': '片A',
                'vod_pic': '',
              },
            ],
          ),
        ),
      );
      final Result<HomeContentResult> r = await uc.homeContent('cms');
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(r.valueOrNull!.classes!.single.typeName, '电影');
      expect(r.valueOrNull!.list!.single.vodName, '片A');
    });

    test('CMS 未注入数据源 → UnsupportedFailure', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'cms', type: 1, api: 'https://cms.example.com'),
          ]),
        ),
      );
      expect(
        (await uc.homeContent('cms')).failureOrNull,
        isA<UnsupportedFailure>(),
      );
    });

    test('蜘蛛路径：register + callHomeContent + dispose', () async {
      final _FakeSpiderEngine engine = _FakeSpiderEngine(
        SpiderEngineType.node,
        homeResult: HomeContentResult(
          list: <VodItem>[
            VodItem.fromJson(
                <String, Object?>{'vod_id': '1', 'vod_name': '片', 'vod_pic': ''}),
          ],
        ),
      );
      final _FakeSpiderEngineFactory factory = _FakeSpiderEngineFactory(engine);
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'nodejs_x', type: 3),
          ]),
        ),
        engineFactory: factory,
      );
      final Result<HomeContentResult> r = await uc.homeContent('nodejs_x');
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(r.valueOrNull!.list!.single.vodName, '片');
      expect(factory.createdTypes.single, SpiderEngineType.node);
      expect(engine.calls, contains('registerSpider'));
      expect(engine.calls, contains('homeContent'));
      expect(engine.calls.last, 'dispose');
    });
  });

  group('categoryContent', () {
    test('CMS 路径：带 tid 的 videolist', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'cms', type: 0, api: 'https://cms.example.com'),
          ]),
        ),
        cmsDatasource: CmsV10Datasource(
          client: cmsClient(
            list: <Map<String, Object?>>[
              <String, Object?>{
                'vod_id': '2',
                'vod_name': '片B',
                'vod_pic': '',
                'vod_remarks': '更新至8集',
              },
            ],
          ),
        ),
      );
      final Result<CategoryContentResult> r =
          await uc.categoryContent('cms', tid: '1', page: 2);
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(r.valueOrNull!.page, 2);
      expect(r.valueOrNull!.list!.single.vodName, '片B');
      expect(r.valueOrNull!.list!.single.vodRemarks, '更新至8集');
    });

    test('蜘蛛路径：callCategoryContent(tid, pg)', () async {
      final _FakeSpiderEngine engine = _FakeSpiderEngine(
        SpiderEngineType.node,
        categoryResult: CategoryContentResult(
          page: 1,
          list: <VodItem>[
            VodItem.fromJson(
                <String, Object?>{'vod_id': '1', 'vod_name': '片', 'vod_pic': ''}),
          ],
        ),
      );
      final _FakeSpiderEngineFactory factory = _FakeSpiderEngineFactory(engine);
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'nodejs_x', type: 3),
          ]),
        ),
        engineFactory: factory,
      );
      final Result<CategoryContentResult> r =
          await uc.categoryContent('nodejs_x', tid: '9', page: 2);
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(engine.calls, contains('categoryContent:9:2'));
      expect(engine.calls.last, 'dispose');
    });
  });

  group('categories', () {
    test('CMS 路径：fetchCategories → VodCategory 列表', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'cms', type: 0, api: 'https://cms.example.com'),
          ]),
        ),
        cmsDatasource: CmsV10Datasource(
          client: cmsClient(
            classes: <Map<String, Object?>>[
              <String, Object?>{'type_id': '1', 'type_name': '电影'},
              <String, Object?>{'type_id': '2', 'type_name': '剧集'},
            ],
          ),
        ),
      );
      final Result<List<VodCategory>> r = await uc.categories('cms');
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(r.valueOrNull!.map((VodCategory c) => c.typeName),
          <String>['电影', '剧集']);
    });

    test('蜘蛛路径：callHomeContent().classes', () async {
      final _FakeSpiderEngine engine = _FakeSpiderEngine(
        SpiderEngineType.node,
        homeResult: HomeContentResult(
          classes: <VodCategory>[
            VodCategory.fromJson(
                <String, Object?>{'type_id': '9', 'type_name': '动漫'}),
          ],
        ),
      );
      final _FakeSpiderEngineFactory factory = _FakeSpiderEngineFactory(engine);
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'nodejs_x', type: 3),
          ]),
        ),
        engineFactory: factory,
      );
      final Result<List<VodCategory>> r = await uc.categories('nodejs_x');
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(r.valueOrNull!.single.typeName, '动漫');
      expect(engine.calls, contains('homeContent'));
      expect(engine.calls.last, 'dispose');
    });

    test('空 siteKey → ValidationFailure', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => const Success<AllSourcesContainer>(
          AllSourcesContainer(),
        ),
      );
      expect(
        (await uc.categories('  ')).failureOrNull,
        isA<ValidationFailure>(),
      );
    });
  });

  group('searchContent', () {
    test('空关键词 → ValidationFailure', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => const Success<AllSourcesContainer>(
          AllSourcesContainer(),
        ),
      );
      expect(
        (await uc.searchContent('k', '  ')).failureOrNull,
        isA<ValidationFailure>(),
      );
    });

    test('CMS 路径：带 wd 的 videolist', () async {
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'cms', type: 0, api: 'https://cms.example.com'),
          ]),
        ),
        cmsDatasource: CmsV10Datasource(
          client: cmsClient(
            list: <Map<String, Object?>>[
              <String, Object?>{
                'vod_id': '3',
                'vod_name': '片C',
                'vod_pic': '',
              },
            ],
          ),
        ),
      );
      final Result<SearchContentResult> r =
          await uc.searchContent('cms', '片C');
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(r.valueOrNull!.list!.single.vodName, '片C');
    });

    test('蜘蛛路径：callSearchContent(keyword, pg)', () async {
      final _FakeSpiderEngine engine = _FakeSpiderEngine(
        SpiderEngineType.node,
        searchResult: SearchContentResult(
          page: 1,
          list: <VodItem>[
            VodItem.fromJson(
                <String, Object?>{'vod_id': '1', 'vod_name': '片', 'vod_pic': ''}),
          ],
        ),
      );
      final _FakeSpiderEngineFactory factory = _FakeSpiderEngineFactory(engine);
      final ContentBrowseUseCases uc = ContentBrowseUseCases(
        loadAllSources: () async => Success<AllSourcesContainer>(
          buildContainer(<Map<String, Object?>>[
            siteJson(key: 'nodejs_x', type: 3),
          ]),
        ),
        engineFactory: factory,
      );
      final Result<SearchContentResult> r =
          await uc.searchContent('nodejs_x', '关键词', page: 2);
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(engine.calls, contains('searchContent:关键词:2'));
      expect(engine.calls.last, 'dispose');
    });
  });
}