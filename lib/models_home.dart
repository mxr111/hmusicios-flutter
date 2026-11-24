import 'models.dart';

/// 网易云独立首页数据。与华为发现页数据分开存放，避免两套推荐流互相污染。
class NeteaseHomeData {
  const NeteaseHomeData({
    this.banners = const <NeteaseHomeBanner>[],
    this.playlists = const <Playlist>[],
    this.dailySongs = const <Song>[],
    this.newSongs = const <Song>[],
    this.radioSongs = const <Song>[],
    this.specials = const <NeteaseHomeSpecial>[],
  });

  final List<NeteaseHomeBanner> banners;
  final List<Playlist> playlists;
  final List<Song> dailySongs;
  final List<Song> newSongs;
  final List<Song> radioSongs;
  final List<NeteaseHomeSpecial> specials;

  bool get isEmpty => banners.isEmpty &&
      playlists.isEmpty &&
      dailySongs.isEmpty &&
      newSongs.isEmpty &&
      radioSongs.isEmpty &&
      specials.isEmpty;

  NeteaseHomeData copyWith({
    List<NeteaseHomeBanner>? banners,
    List<Playlist>? playlists,
    List<Song>? dailySongs,
    List<Song>? newSongs,
    List<Song>? radioSongs,
    List<NeteaseHomeSpecial>? specials,
  }) {
    return NeteaseHomeData(
      banners: banners ?? this.banners,
      playlists: playlists ?? this.playlists,
      dailySongs: dailySongs ?? this.dailySongs,
      newSongs: newSongs ?? this.newSongs,
      radioSongs: radioSongs ?? this.radioSongs,
      specials: specials ?? this.specials,
    );
  }
}

/// 网易云首页轮播（/weapi/v2/banner/get）。
class NeteaseHomeBanner {
  const NeteaseHomeBanner({
    required this.title,
    this.subtitle = '',
    this.imageUrl,
    this.targetId = '',
  });

  final String title;
  final String subtitle;
  final Uri? imageUrl;
  final String targetId;
}

/// 独家放送 / 编辑推荐卡（/weapi/personalized/privatecontent）。
class NeteaseHomeSpecial {
  const NeteaseHomeSpecial({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.cover,
  });

  final String id;
  final String title;
  final String subtitle;
  final Uri? cover;
}
