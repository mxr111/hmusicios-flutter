/// REA 从 Muyu.exe 静态提取 + 运行时内存取证确认的华为音乐服务路径。
/// 关键事实：带 ?query 的路径必须原样拼接在域名后（不能把 ? 编码进 path）。
class HuaweiPaths {
  const HuaweiPaths._();

  static const String host = 'api-drcn.music.dbankcloud.cn';
  static const String oauthHost = 'oauth-login.cloud.huawei.com';

  // 首页 / 推荐 / 榜单
  static const String home =
      '/music-operation-service/v1/service/page/detail/all?pageType=7&hasRecommend=1';
  static const String daily = '/music-recommend-service/v1/service/recommend/querydaily';
  static const String privateFm = '/music-recommend-service/v1/service/recommend/privatefm';
  static const String similar = '/music-recommend-service/v2/service/recommend/querysimilar';
  static const String chartDetail = '/music-operation-service/v1/service/chart/detail/bychartid';

  // 搜索 / 详情
  static const String search = '/music-search-service/v10/service/fuzzysearch';
  static const String songDetail = '/music-metacontent-service/v1/service/song/detail/bysongcode';
  static const String albumDetail = '/music-metacontent-service/v1/service/album/detail/byalbumcode';
  static const String artistDetail = '/music-metacontent-service/v1/service/artist/detail/byartistcode';

  // 用户行为
  static const String playlistDetail = '/music-userbehavior-service/v4/service/playlist/detail/all';
  static const String playlistSongs = '/music-userbehavior-service/v1/service/playlist/song/';
  static const String favorites = '/music-userbehavior-service/v5/service/favorite/simple/all';
  static const String favoriteWrite = '/music-userbehavior-service/v1/service/favorite/';
  static const String favoriteExist =
      '/music-userbehavior-service/v1/service/favorite/simple/exist';
  static const String recent =
      '/music-userbehavior-service/v1/service/recentlyplayed/query?contentType=1';

  // 取流 / 会员 / 登录 / 评论
  static const String playUrl = '/music-play-service/v3/service/file/bycontentcode';
  static const String subscription =
      '/music-order-service/v4/service/subscription/detail?domainTypes=1&domainTypes=6';
  static const String userInfo = '/music-odpapp-service/v5/service/userinfo/login';
  static const String comments = '/music-sns-service/v1/service/comment/query';

  // OAuth（原生版用 PKCE；Flutter 版保留常量供后续接入）
  static const String authorize = '/oauth2/v3/authorize';
  static const String token = '/oauth2/v3/token';
  static const String clientId = '101444301';
  static const String redirectUri = 'hms://redirect_uri';

  /// 设备伪装串：REA 观察到的完整值
  static const String deviceContext =
      'model=HBN-AL00,brand=HUAWEI,rom=0,emui=0,os=12,apilevel=31,'
      'manufacturer=HUAWEI,useBrandCust=false,harmonyApiLevel=0,huaweiOsBrand=';
  static const String clientVersion = '12.11.37.310';
  static const String packageName = 'com.huawei.music';
}
