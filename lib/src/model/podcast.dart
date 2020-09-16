// Copyright (c) 2019, Ben Hills. Use of this source code is governed by a
// MIT license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_rss/dart_rss.dart';
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:podcast_search/podcast_search.dart';
import 'package:podcast_search/src/model/episode.dart';
import 'package:podcast_search/src/utils/utils.dart';

/// This class represents a podcast and its episodes. The Podcast is instantiated with a feed URL which is
/// then parsed and the episode list generated.
class Podcast {
  final String url;
  final String link;
  final String title;
  final String description;
  final String image;
  final String copyright;
  final List<Episode> episodes;

  Podcast._(
    this.url, [
    this.link,
    this.title,
    this.description,
    this.image,
    this.copyright,
    this.episodes,
  ]);

  static Future<Podcast> loadFeed({
    @required String url,
    int timeout = 20000,
    Duration cacheDuration,
    Directory cacheDirectory
  }) async {
    try {
      var rssFeed = await _loadRssFeed(
        url: url,
        timeout: timeout,
        cacheDuration: cacheDuration,
        cacheDirectory: cacheDirectory,
      );

      // Parse the episodes
      var episodes = <Episode>[];
      var author = rssFeed.author ?? rssFeed.itunes.author;

      _loadEpisodes(rssFeed, episodes);

      return Podcast._(url, rssFeed.link, rssFeed.title, rssFeed.description,
          rssFeed.image?.url, author, episodes);
    } on DioError catch (e) {
      switch (e.type) {
        case DioErrorType.CONNECT_TIMEOUT:
        case DioErrorType.SEND_TIMEOUT:
        case DioErrorType.RECEIVE_TIMEOUT:
        case DioErrorType.DEFAULT:
          throw PodcastTimeoutException(e.message);
          break;
        case DioErrorType.RESPONSE:
          throw PodcastFailedException(e.message);
          break;
        case DioErrorType.CANCEL:
          throw PodcastCancelledException(e.message);
          break;
      }
    }

    return Podcast._(url);
  }

  static Future<RssFeed> _loadRssFeed({
    @required String url,
    int timeout = 20000,
    Duration cacheDuration,
    Directory cacheDirectory
  }) async {
    final client = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        headers: {
          HttpHeaders.userAgentHeader: 'podcast_search Dart/1.0',
        },
      ),
    );

    // If no cache duration is passed in, just load the feed normally
    if (cacheDuration == null) {
      final response = await client.get(url);

      return RssFeed.parse(response.data);
    }

    final cacheFile = await _cacheFile(url: url, cacheDirectory: cacheDirectory);

    print(cacheFile.path);

    // If there is a cache file that has not expired, load it
    if (cacheFile.existsSync() && cacheFile.lastModifiedSync().add(cacheDuration).isBefore(DateTime.now())) {
      return RssFeed.parse(cacheFile.readAsStringSync());
    }

    final response = await client.get(url);

    // Save feed in the cache
    cacheFile.writeAsStringSync(response.data);

    return RssFeed.parse(response.data);
  }

  static Future<File> _cacheFile({String url, Directory cacheDirectory}) async {
    if (cacheDirectory.existsSync() == false) {
      cacheDirectory.createSync();
    }

    final filename = url.split('://').last.replaceAll('/', '_');

    return File('${cacheDirectory.path}/${filename}');
  }

  static void _loadEpisodes(RssFeed rssFeed, List<Episode> episodes) {
    rssFeed.items.forEach((item) {
      episodes.add(Episode.of(
          item.guid,
          item.title,
          item.description,
          item.link,
          Utils.parseRFC2822Date(item.pubDate),
          item.author ?? item.itunes.author,
          item.itunes?.duration,
          item.enclosure?.url,
          item.itunes?.season,
          item.itunes?.episode));
    });
  }
}
