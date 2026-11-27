# 登录会话与 1 小时自动重登说明

## 账号密码落盘

- 华为账号和密码只作为 OAuth 授权页的自动填充/重新登录辅助，不用于华为账号密码直登。
- `PreferencesSessionStore` 使用已有 `encrypt` 包做 AES-256-CBC（PKCS7）加密。
- 每次保存凭据生成随机 32 字节 AES key 和随机 16 字节 IV，Base64 后写入
  `muyu.session.v1` 的 `credentialKey` / `credentialIv`。
- 账号与密码分别是 `huaweiAccountEncrypted` / `huaweiPasswordEncrypted`，
  普通会话/设置持久化不会覆盖这组加密字段。
- 明文账号/密码不进入 JSON、日志或异常文本。`clear()` 与 `clearCredentials()`
  都会清理凭据。
- 这是本机 SharedPreferences 内的静态加密，key 与密文同库保存；它不是
  Android Keystore / iOS Keychain 的硬件级密钥保护。

## 会话保活

- `MuyuApp._bootstrap()` 恢复会话后调用 `AppState.startSessionKeepAlive()`。
- `Timer.periodic(Duration(hours: 1))` 触发一次静默续期；重复调用不会创建多个 timer，
  `dispose()` 会取消 timer。
- 续期优先使用 OAuth `refresh_token`：表单 POST 到
  `https://oauth-login.cloud.huawei.com/oauth2/v3/token`，字段为
  `grant_type=refresh_token`、`client_id`、`refresh_token`。
- 拿到新的账号 access token 后调用 `loginex` 换音乐会话，再刷新资料、持久化会话并
  重新加载曲库。上游未返回新 `refresh_token` 时沿用旧值。
- 若 refresh token 不可用，再尝试现有账号 access token 换音乐会话。

## 仍需用户重新授权一次的原因

- 华为 OAuth 授权码仍然只能由用户在华为授权页完成一次；本机没有账号密码直登协议。
- 服务端可能轮换/撤销 refresh token，或音乐会话返回 `990000` /
  token expired；此时无法纯静默恢复。
- 若本机保存了账号密码，失败后会设置 `needsRelogin = true`，由 `main.dart`
  自动打开启用 `autoFillCredentials` 的 OAuth WebView。WebView 只在华为页面
  注入账号/密码并尝试提交，最终仍需用户手动完成验证码、二次验证或授权。
- 因此“1 小时自动重登”是 OAuth 静默续期 + 本地凭据辅助填充的回退链，不是
  绕过华为登录；真机遇到 `990000` 时仍可能需要用户重新登录一次以刷新 OAuth 会话。
