import 'package:flutter/material.dart' show ThemeMode;

enum DisplayMode { grid, list }

enum SearchHistorySort { recent, count }

/// Represents a video source site (spider site)
class VodSite {
  final String key;
  final String name;
  final String api;
  final String? ext;
  final bool searchable;
  final bool? playUrl;
  final String? home;
  final String? category;

  VodSite({
    required this.key,
    required this.name,
    required this.api,
    this.ext,
    this.searchable = true,
    this.playUrl,
    this.home,
    this.category,
  });

  factory VodSite.fromJson(Map<String, dynamic> json) {
    return VodSite(
      key: json['key'] as String,
      name: json['name'] as String? ?? json['key'] as String,
      api: json['api'] as String? ?? '',
      ext: json['ext'] as String?,
      searchable: json['searchable'] as bool? ?? true,
      playUrl: json['playUrl'] as bool?,
      home: json['home'] as String?,
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'api': api,
        'ext': ext,
        'searchable': searchable,
        'playUrl': playUrl,
        'home': home,
        'category': category,
      };
}

/// Represents a video (VOD) entry
class Vod {
  final String id;
  final String name;
  final String? pic;
  final String? from;
  final String? siteKey;
  final String? year;
  final String? area;
  final String? director;
  final String? actor;
  final String? tag;
  final String? remarks;
  final String? playFrom;
  final String? playUrl;
  final List<PlaySource> playSources;

  Vod({
    required this.id,
    required this.name,
    this.pic,
    this.from,
    this.siteKey,
    this.year,
    this.area,
    this.director,
    this.actor,
    this.tag,
    this.remarks,
    this.playFrom,
    this.playUrl,
    this.playSources = const [],
  });

  factory Vod.fromJson(Map<String, dynamic> json) {
    final sources = (json['list'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(PlaySource.fromJson)
            .toList() ??
        (json['playSources'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(PlaySource.fromJson)
            .toList() ??
        const <PlaySource>[];
    return Vod(
      id: json['vod_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['vod_name']?.toString() ?? json['name']?.toString() ?? '',
      pic: json['vod_pic']?.toString() ?? json['pic']?.toString(),
      from: json['vod_from']?.toString() ?? json['from']?.toString(),
      siteKey: json['site_key']?.toString() ?? json['siteKey']?.toString(),
      year: json['vod_year']?.toString() ?? json['year']?.toString(),
      area: json['vod_area']?.toString() ?? json['area']?.toString(),
      director: json['vod_director']?.toString() ?? json['director']?.toString(),
      actor: json['vod_actor']?.toString() ?? json['actor']?.toString(),
      tag: json['vod_tag']?.toString() ?? json['tag']?.toString(),
      remarks: json['vod_remarks']?.toString() ?? json['remarks']?.toString(),
      playFrom: json['vod_play_from']?.toString() ?? json['playFrom']?.toString(),
      playUrl: json['vod_play_url']?.toString() ?? json['playUrl']?.toString(),
      playSources: sources,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pic': pic,
        'from': from,
        'siteKey': siteKey,
        'year': year,
        'area': area,
        'director': director,
        'actor': actor,
        'tag': tag,
        'remarks': remarks,
        'playFrom': playFrom,
        'playUrl': playUrl,
      };
}

/// Represents a play source (episode group)
class PlaySource {
  final String from;
  final List<PlayItem> list;

  PlaySource({required this.from, required this.list});

  factory PlaySource.fromJson(Map<String, dynamic> json) {
    return PlaySource(
      from: json['from'] as String,
      list: (json['list'] as List<dynamic>?)
          ?.map((e) => PlayItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
    );
  }
}

class PlayItem {
  final String name;
  final String url;

  PlayItem({required this.name, required this.url});

  factory PlayItem.fromJson(Map<String, dynamic> json) {
    return PlayItem(
      name: json['name'] as String,
      url: json['url'] as String,
    );
  }
}

/// Live source entry
class LiveSource {
  final String name;
  final String url;
  final String? logo;
  final int? liveOffset;
  final int? liveOffsetMs;

  LiveSource({
    required this.name,
    required this.url,
    this.logo,
    this.liveOffset,
    this.liveOffsetMs,
  });

  factory LiveSource.fromJson(Map<String, dynamic> json) {
    return LiveSource(
      name: json['name'] as String,
      url: json['url'] as String,
      logo: json['logo'] as String?,
      liveOffset: json['liveOffset'] as int?,
      liveOffsetMs: json['liveOffsetMs'] as int?,
    );
  }
}

/// Pan (cloud storage) configuration
class PanConfig {
  final String type;
  final String? token;
  final String? cookie;
  final String? baseUrl;

  PanConfig({
    required this.type,
    this.token,
    this.cookie,
    this.baseUrl,
  });
}

/// Search history entry
class SearchHistory {
  final int? id;
  final String keyword;
  final int count;
  final int timestamp;

  SearchHistory({
    this.id,
    required this.keyword,
    required this.count,
    required this.timestamp,
  });

  factory SearchHistory.fromJson(Map<String, dynamic> json) {
    return SearchHistory(
      id: json['id'] as int?,
      keyword: json['keyword'] as String,
      count: json['count'] as int? ?? 0,
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'keyword': keyword,
        'count': count,
        'timestamp': timestamp,
      };
}

/// Watch history entry
class WatchHistory {
  final int? id;
  final String vodId;
  final String vodName;
  final String? siteKey;
  final int positionMs;
  final int timestamp;

  WatchHistory({
    this.id,
    required this.vodId,
    required this.vodName,
    this.siteKey,
    this.positionMs = 0,
    required this.timestamp,
  });

  factory WatchHistory.fromJson(Map<String, dynamic> json) {
    return WatchHistory(
      id: json['id'] as int?,
      vodId: json['vodId'] as String,
      vodName: json['vodName'] as String,
      siteKey: json['siteKey'] as String?,
      positionMs: json['positionMs'] as int? ?? 0,
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'vodId': vodId,
        'vodName': vodName,
        'siteKey': siteKey,
        'positionMs': positionMs,
        'timestamp': timestamp,
      };
}

/// Player state
enum PlayerState { idle, loading, playing, paused, error }

/// Represents a player episode
class PlayerEpisode {
  final String title;
  final String url;

  PlayerEpisode({required this.title, required this.url});
}