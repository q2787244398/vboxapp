/// 数据层单测：豆瓣数据源（批次 D · D-03）。
///
/// 注入 http MockClient 到 [HttpClient]，验证 rexxar 合集与 chart 榜单的
/// 请求 URL、JSON 解析与容错（非 2xx / 非 JSON）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vbox/core/errors/exceptions.dart';
import 'package:vbox/core/network/http_client.dart';
import 'package:vbox/data/datasources/remote/douban_datasource.dart';
import 'package:vbox/domain/entities/douban/douban_models.dart';

void main() {
  group('DoubanDatasource.fetchCollection', () {
    test('解析 subject_collection_items', () async {
      final MockClient mock = MockClient((http.Request request) async {
        expect(
          request.url.toString(),
          startsWith(
            '${DoubanDatasource.baseURL}/subject_collection/movie_hot_gaia/items',
          ),
        );
        return http.Response(
          jsonEncode(<String, Object?>{
            'subject_collection_items': <Map<String, Object?>>[
              <String, Object?>{
                'id': '1001',
                'title': '片A',
                'rating': <String, Object?>{'value': 8.5, 'count': 100},
                'year': '2024',
                'genres': <String>['剧情', '犯罪'],
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final DoubanDatasource ds =
          DoubanDatasource(client: HttpClient(inner: mock));
      final List<DoubanSubject> list =
          await ds.fetchCollection('movie_hot_gaia');

      expect(list, hasLength(1));
      expect(list.single.id, '1001');
      expect(list.single.title, '片A');
      expect(list.single.rating, 8.5);
      expect(list.single.ratingCount, 100);
      expect(list.single.genres, <String>['剧情', '犯罪']);
      expect(list.single.hasRating, isTrue);
    });

    test('非 2xx → NetworkException', () async {
      final MockClient mock = MockClient(
        (http.Request request) async => http.Response('forbidden', 403),
      );
      final DoubanDatasource ds =
          DoubanDatasource(client: HttpClient(inner: mock));

      expect(
        () => ds.fetchCollection('movie_hot_gaia'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('DoubanDatasource.fetchChartRanking', () {
    test('解析 chart top_list 数组（缺失 rank 用序号补位）', () async {
      final MockClient mock = MockClient((http.Request request) async {
        expect(request.url.host, 'movie.douban.com');
        expect(request.url.path, '/j/chart/top_list');
        return http.Response(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': '1',
              'title': '榜A',
              'cover_url': '//img.douban.com/a.jpg',
              'score': '9.2',
              'vote_count': 500,
              'release_date': '2023-01-01',
              'types': <String>['剧情', '犯罪'],
            },
            <String, Object?>{
              'id': '2',
              'title': '榜B',
              'rank': 3,
              'score': '8.0',
              'release_date': '2022-05-01',
            },
          ]),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final DoubanDatasource ds =
          DoubanDatasource(client: HttpClient(inner: mock));
      final List<DoubanChartSubject> list = await ds.fetchChartRanking(
        DoubanChartCategory.all.first,
        start: 0,
      );

      expect(list, hasLength(2));
      expect(list[0].rank, 1); // 缺省 rank → 序号补位
      expect(list[0].rating, 9.2);
      expect(list[0].year, '2023');
      expect(list[0].info, '剧情 / 犯罪');
      expect(list[0].coverUrl, 'https://img.douban.com/a.jpg');
      expect(list[1].rank, 3); // 显式 rank
    });
  });
}