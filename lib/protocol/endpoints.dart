/// 华为音乐服务路径。
/// 事实来源：REA 对 Muyu.exe 静态+运行时取证，并以同源项目 tinglan 的
/// docs/API_CONTRACT.md（真人账号验证）与 Go 源码交叉校正。
/// 关键：带 ?query 的路径必须原样拼在域名后（不能把 ? 编码进 path）。
class HuaweiPaths {
  const HuaweiPaths._();

  static const String host = 'api-drcn.music.dbankcloud.cn';

  /// 授权入口域名：源码事实 oauth-login.platform.hicloud.com
  /// （之前误用 oauth-login.cloud.huawei.com）。
  static const String authorizeHost = 'oauth-login.platform.hicloud.com';

  /// 授权码兑换域名：源码事实 oauth-login.cloud.huawei.com。
  static const String tokenHost = 'oauth-login.cloud.huawei.com';
  static const String authorizePath = '/oauth2/v3/authorize';
  static const String tokenPath = '/oauth2/v3/token';
  static const String userInfoPath = '/oauth2/v3/userinfo';

  // 音乐会话（三段式第 3 步：账号 AT -> 音乐 token）
  static const String loginEx = '/music-odpapp-service/v5/service/userinfo/loginex';

  /// 音乐侧账号资料：登录后用音乐 token 读取，避免只依赖 OAuth 的
  /// profile scope / 短期账号 AT。字段实测包含 nickname/avatarUrl 一类。
  static const String musicUserInfo = '/music-odpapp-service/v5/service/userinfo';

  // 首页 / 推荐 / 榜单（tinglan 契约：querydaily/privatefm 等未验证，保留但可能 400）
  static const String home = '/music-operation-service/v1/service/page/detail/all?pageType=7&hasRecommend=1';
  static const String daily = '/music-recommend-service/v1/service/recommend/querydaily';
  static const String recommendPlaylist = '/music-recommend-service/v1/service/recommend/playlist';
  static const String privateFm = '/music-recommend-service/v1/service/recommend/privatefm';
  static const String similar = '/music-recommend-service/v2/service/recommend/querysimilar';
  static const String chartDetail = '/music-operation-service/v1/service/chart/detail/bychartid';

  // 搜索 / 详情
  static const String search = '/music-search-service/v10/service/fuzzysearch';
  static const String songDetail = '/music-metacontent-service/v1/service/song/detail/bysongcode';
  static const String albumDetail = '/music-metacontent-service/v1/service/album/detail/byalbumcode';
  static const String artistDetail = '/music-metacontent-service/v1/service/artist/detail/byartistcode';

  /// 2.0.4 运行时实测：歌手详情走 v2 POST，body 需 songNum/albumNum。
  static const String artistDetailV2 = '/music-metacontent-service/v2/service/artist/detail/byartistcode';

  /// 歌手歌曲（REA 26 路径实测：/song/simple/byartistcode）。
  static const String artistSongs = '/music-metacontent-service/v1/service/song/simple/byartistcode';
  static const String mvFile = '/music-metacontent-service/v1/service/mvfile/bymvid';

  // 用户行为（音源插件 huawei-source.exe 实际包含的接口）
  /// 歌单发现：与收藏列表同一接口，contentTypes=[4,5,7]。
  static const String playlistDetail = '/music-userbehavior-service/v3/service/favorite/simple/all';

  /// 收藏歌单（type=4 collected）详情。
  static const String playlistSongs = '/music-operation-service/v2/service/musiclist/detail/bymusiclistid';

  /// 自建歌单（type=5 owned）详情，GET + playListID/start/limit。
  static const String ownedPlaylistSongs = '/music-userbehavior-service/v1/service/playlist/detail/all';

  /// 2.0.4 新增的 v4 用户歌单详情（运行时内存实测路径常量）。
  static const String userPlaylistDetailV4 = '/music-userbehavior-service/v4/service/playlist/detail/all';
  static const String favorites = '/music-userbehavior-service/v5/service/favorite/simple/all';
  static const String favoriteCreate = '/music-userbehavior-service/v1/service/favorite/create';
  static const String favoriteDelete = '/music-userbehavior-service/v1/service/favorite/delete';
  static const String favoriteExist = '/music-userbehavior-service/v1/service/favorite/simple/exist';
  static const String recent = '/music-userbehavior-service/v1/service/recentlyplayed/query?contentType=1';
  static const String playlistCreate = '/music-userbehavior-service/v1/service/playlist/create';
  static const String playlistDelete = '/music-userbehavior-service/v1/service/playlist/delete';
  static const String playlistChangeSong = '/music-userbehavior-service/v1/service/playlist/changesong';

  // 取流 / 会员 / 评论
  static const String playUrl = '/music-play-service/v3/service/file/bycontentcode';
  static const String subscription = '/music-order-service/v4/service/subscription/detail?domainTypes=1&domainTypes=6';
  static const String comments = '/music-sns-service/v1/service/comment/query';

  // OAuth 常量（真人验证）
  static const String clientId = '101444301';
  static const String redirectUri = 'hms://redirect_uri';

  /// 业务成功码（源码事实：result.resultCode == "000000"）。
  static const String successCode = '000000';

  /// 设备伪装串：REA 观察到；tinglan 契约强调不强依赖设备头，保留兼容。
  static const String deviceContext = 'model=HBN-AL00,brand=HUAWEI,rom=0,emui=0,os=12,apilevel=31,'
      'manufacturer=HUAWEI,useBrandCust=false,harmonyApiLevel=0,huaweiOsBrand=';
  static const String clientVersion = '12.11.37.310';
  static const String packageName = 'com.huawei.music';
}
