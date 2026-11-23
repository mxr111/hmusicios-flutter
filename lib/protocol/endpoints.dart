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

  // 音乐会话（三段式第 3 步：账号 AT -> 音乐 token）
  static const String loginEx = '/music-odpapp-service/v5/service/userinfo/loginex';

  // 首页 / 推荐 / 榜单（tinglan 契约：querydaily/privatefm 等未验证，保留但可能 400）
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
  static const String artistDetail = '/music-metacontent-service/v2/service/artist/detail/byartistcode';

  // 用户行为（API_CONTRACT 校正后的真实路径）
  static const String playlistDetail =
      '/music-userbehavior-service/v1/service/playlist/detail/all';
  static const String playlistSongs =
      '/music-userbehavior-service/v1/service/playlist/detail/all';
  static const String favorites =
      '/music-userbehavior-service/v3/service/favorite/simple/all';
  static const String favoriteCreate =
      '/music-userbehavior-service/v1/service/favorite/create';
  static const String favoriteDelete =
      '/music-userbehavior-service/v1/service/favorite/delete';
  static const String favoriteExist =
      '/music-userbehavior-service/v1/service/favorite/simple/exist';
  static const String recent =
      '/music-userbehavior-service/v1/service/recentlyplayed/query?contentType=1';

  // 取流 / 会员 / 评论
  static const String playUrl = '/music-play-service/v3/service/file/bycontentcode';
  static const String subscription =
      '/music-order-service/v4/service/subscription/detail?domainTypes=1&domainTypes=6';
  static const String comments = '/music-sns-service/v1/service/comment/query';

  // OAuth 常量（真人验证）
  static const String clientId = '101444301';
  static const String redirectUri = 'hms://redirect_uri';

  /// 业务成功码（源码事实：result.resultCode == "000000"）。
  static const String successCode = '000000';

  /// 设备伪装串：REA 观察到；tinglan 契约强调不强依赖设备头，保留兼容。
  static const String deviceContext =
      'model=HBN-AL00,brand=HUAWEI,rom=0,emui=0,os=12,apilevel=31,'
      'manufacturer=HUAWEI,useBrandCust=false,harmonyApiLevel=0,huaweiOsBrand=';
  static const String clientVersion = '12.11.37.310';
  static const String packageName = 'com.huawei.music';
}
