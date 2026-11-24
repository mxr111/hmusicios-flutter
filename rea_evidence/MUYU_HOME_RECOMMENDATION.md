# 沐语 2.0.4 首页 / 推荐流 / 音质 REA 结论

本次重新用 Ghidra 12.1.4 对 `Muyu-2.0.4-Windows-x64.exe` 的 Go 符号反编译，
并结合 `C:\沐语\independent-data\native-ui.json`、二进制字符串与运行截图交叉验证。

## 1. 首页不是一条“新歌流”

沐语自己的更新日志（二进制内嵌 UTF-8）明确写：

- 1.1.1：全新主页提供「现在就听」「每日30首」「心动模式」卡片，以及推荐歌曲和推荐歌单；
  「现在就听」拥有独立曲库，可自动补充新歌；接入独立的「为你推荐」歌曲。
- 1.1.10：修复华为首页未返回首批歌曲时「现在就听」无法起播；改善首页私享好歌。
- 2.0.4 运行时 `native-ui.json` 的 `playback.source` 为：

```json
{"kind":"radio","id":"listen","scope":"5659a08acf137644","next":104,"more":true}
```

`playback.queue` 是一个独立电台队列（当前账号 104 首以上），不是首页的
`newSongs`。「现在就听」三张封面随队列上一首/下一首推进。

## 2. 「为你推荐」= 私享好歌栏目

Ghidra 反编译 `muyu.local/desktop/internal/gateway.(*Connection).RadioMode`
（`0x1404258c0`）得到以下常量：

- `recom_exclusive`
- `8011`
- `GET /music-operation-service/v1/service/column/detail/bycolumnid?`
- `columnID` / `columnId` / `hasRecommend`
- 错误文案：「首页未返回私享好歌列表或栏目编号」「栏目详情未返回私享好歌列表」

因此「为你推荐」不是 `page/detail/all` 里随便挑的歌曲，而是：

1. 首页 JSON 找 `recom_exclusive` 栏目；
2. 取得栏目编号（当前二进制常量兜底为 `8011`）；
3. GET `column/detail/bycolumnid?columnId=...&start=0&limit=30&hasRecommend=1`；
4. 从 `columnInfoExs/contentSimpleInfos/listRcmInfos/songSimpleInfos` 取歌。

本次 Flutter 实现：

- `HuaweiAPI.parseDiscover` 按栏目拆分 `newSongs / listen / heart / hot / recommended`；
- `HuaweiAPI.discover()` 在首页没有直接给私享好歌时按 `8011` 拉栏目详情；
- `AppState.loadHome` 的 `homeSongs` 改用 `recommended`（私享好歌），不再用 `newSongs`；
- 栏目为空才回退到首页电台；不伪造推荐。

## 3. 音质

`native-ui.json`：

```json
"quality": "hires",
"platformQuality": {"kugou":"viper_clear","netease":"jymaster","qq":"RS01"}
```

`playback.queue` 里的 `confirmedAudio` 显示：请求 `hires` 时实际可能是
`hires(48kHz/24bit)` 或 `lossless(44.1kHz/16bit)`，说明是**先请求最高档，
再按上游实际可用档回退**。

本次 Flutter 实现：

- 默认 `AudioController.quality = hiRes`；
- `Song.qualities` 解析 `hiResAvailable`、`highestQuality`、
  `huaweiAudioFiles.types`、`fileInfos/qualityType`、`size_*`；
- `audioFiles` 按 Hi-Res → 无损/HQ → 标准兜底请求；
- `chooseQuality` 若用户没有明确选低档，则选择上游返回的最高档；
- 不再把标准 MP3 强制塞进每首歌的上游档位集合。

## 4. 复现工具

- `tools/DecompileRanges.java`：按地址反编译 Ghidra 函数；
- `tools/PrintFunctionAt.java`：打印函数边界；
- `tools/symbol_at.py`：按 VA 查 Go pclntab 符号；
- `tools/json_shape.py`：查看沐语 JSON 状态结构；
- `tools/home_targets.tsv` / `radio_targets.tsv`：本次反编译目标。

生成的反编译全文（`home_decomp*.txt` / `radio_decomp.txt`）已加入 `.gitignore`，
结论以本文件为准。
