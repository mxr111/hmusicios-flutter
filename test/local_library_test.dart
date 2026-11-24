import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/services/local_library.dart';

// 全部夹具都在内存中构造，不读取系统文件、不联网。
Uint8List _u8(List<int> data) => Uint8List.fromList(data);

List<int> _syncSafe(int value) => <int>[
      (value >> 21) & 0x7f,
      (value >> 14) & 0x7f,
      (value >> 7) & 0x7f,
      value & 0x7f,
    ];

List<int> _be32(int value) => <int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

List<int> _le32(int value) => <int>[
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ];

/// ID3v2 文本帧内容：[编码字节][文本]。
List<int> _id3Text(String text, {int encoding = 3}) {
  final body = switch (encoding) {
    0 => latin1.encode(text),
    1 => <int>[
        0xff,
        0xfe,
        for (final unit in text.codeUnits) ...<int>[
          unit & 0xff,
          (unit >> 8) & 0xff,
        ],
      ],
    3 => utf8.encode(text),
    _ => throw ArgumentError.value(encoding, 'encoding'),
  };
  return <int>[encoding, ...body];
}

List<int> _id3Frame(String id, List<int> body, {int version = 3}) => <int>[
      ...latin1.encode(id),
      ...(version == 4 ? _syncSafe(body.length) : _be32(body.length)),
      0,
      0,
      ...body,
    ];

Uint8List _id3Tag(
  List<List<int>> frames, {
  int version = 3,
  int padding = 0,
}) {
  final body = <int>[
    for (final frame in frames) ...frame,
    ...List<int>.filled(padding, 0),
  ];
  return _u8(<int>[
    ...latin1.encode('ID3'),
    version,
    0,
    0,
    ..._syncSafe(body.length),
    ...body,
  ]);
}

List<int> _flacBlock(int type, List<int> data, {bool last = false}) {
  final size = data.length;
  return <int>[
    (last ? 0x80 : 0) | type,
    (size >> 16) & 0xff,
    (size >> 8) & 0xff,
    size & 0xff,
    ...data,
  ];
}

List<int> _vorbisComment(List<String> comments) {
  final vendor = utf8.encode('muyu-test');
  return <int>[
    ..._le32(vendor.length),
    ...vendor,
    ..._le32(comments.length),
    for (final comment in comments) ...<int>[
      ..._le32(utf8.encode(comment).length),
      ...utf8.encode(comment),
    ],
  ];
}

Uint8List _flacTag(List<String> comments) => _u8(<int>[
      ...latin1.encode('fLaC'),
      ..._flacBlock(0, List<int>.filled(34, 0)),
      ..._flacBlock(4, _vorbisComment(comments), last: true),
    ]);

void main() {
  test('ID3v2.3：syncsafe 头长度、BE32 大帧与 latin1 标签', () {
    final longTitle = 'A' * 200;
    final tag = _id3Tag(
      <List<int>>[
        _id3Frame('TIT2', _id3Text(longTitle, encoding: 0)),
        _id3Frame('TPE1', _id3Text('Café Artist', encoding: 0)),
        _id3Frame('TALB', _id3Text('Album', encoding: 0)),
      ],
      padding: 100,
    );

    // 头长度必须用 syncsafe；数据量超过 127 时它与普通 BE32 不同。
    expect(tag.sublist(6, 10), _syncSafe(tag.length - 10));
    expect(tag.sublist(6, 10), isNot(equals(_be32(tag.length - 10))));

    final tags = readLocalTags(tag, fallbackName: 'ignored.mp3');
    expect(tags.title, longTitle);
    expect(tags.artist, 'Café Artist');
    expect(tags.album, 'Album');
  });

  test('ID3v2.3：UTF-16LE BOM（编码 1）解析中文', () {
    final tag = _id3Tag(<List<int>>[
      _id3Frame('TIT2', _id3Text('夜曲', encoding: 1)),
      _id3Frame('TPE1', _id3Text('周杰伦', encoding: 1)),
      _id3Frame('TALB', _id3Text('十一月的萧邦', encoding: 1)),
    ]);

    final tags = readLocalTags(tag);
    expect(tags.title, '夜曲');
    expect(tags.artist, '周杰伦');
    expect(tags.album, '十一月的萧邦');
  });

  test('ID3v2.3：UTF-8（编码 3）中文与空文本帧', () {
    final tag = _id3Tag(<List<int>>[
      _id3Frame('TCOM', _id3Text('', encoding: 3)), // 只有编码字节的空帧
      _id3Frame('TIT2', <int>[3]), // 空标题帧，不应中断后续帧
      _id3Frame('TPE1', _id3Text('陈奕迅', encoding: 3)),
      _id3Frame('TALB', _id3Text('认了吧', encoding: 3)),
    ]);

    final tags = readLocalTags(tag);
    expect(tags.title, '');
    expect(tags.artist, '陈奕迅');
    expect(tags.album, '认了吧');
  });

  test('ID3v2.3：零长度帧被跳过，不中断后续帧', () {
    final tag = _id3Tag(<List<int>>[
      _id3Frame('TIT2', const <int>[]),
      _id3Frame('TPE1', _id3Text('周杰伦', encoding: 3)),
    ]);

    final tags = readLocalTags(tag, fallbackName: 'fallback.mp3');
    expect(tags.artist, '周杰伦');
  });

  test('ID3v2.4：帧长度使用 syncsafe 且能解析大帧', () {
    final longTitle = '沐语' * 80; // UTF-8 共 480 字节，帧长度 > 127
    final titleBytes = _id3Text(longTitle, encoding: 3);
    final tag = _id3Tag(
      <List<int>>[
        _id3Frame('TIT2', titleBytes, version: 4),
        _id3Frame('TPE1', _id3Text('周杰伦', encoding: 3), version: 4),
        _id3Frame('TALB', _id3Text('叶惠美', encoding: 3), version: 4),
      ],
      version: 4,
    );

    expect(tag.sublist(6, 10), _syncSafe(tag.length - 10));
    // 标签头 10 字节 + 帧 ID 4 字节之后就是 syncsafe 帧长度。
    expect(tag.sublist(14, 18), _syncSafe(titleBytes.length));
    expect(tag.sublist(14, 18), isNot(equals(_be32(titleBytes.length))));

    final tags = readLocalTags(tag);
    expect(tags.title, longTitle);
    expect(tags.artist, '周杰伦');
    expect(tags.album, '叶惠美');
  });

  test('FLAC：STREAMINFO + 最后一个 VORBIS_COMMENT 解析中文 UTF-8', () {
    final tag = _flacTag(<String>[
      'TITLE=晴天',
      'ARTIST=周杰伦',
      'ALBUM=叶惠美',
      'COMMENT=测试',
    ]);

    // fLaC(4) + STREAMINFO 头与数据(4+34) 后的块头应为 last=1、type=4。
    expect(tag[42], 0x84);

    final tags = readLocalTags(tag, fallbackName: 'ignored.flac');
    expect(tags.title, '晴天');
    expect(tags.artist, '周杰伦');
    expect(tags.album, '叶惠美');
  });

  test('无标签文件：fallbackName 去掉扩展名作为标题', () {
    final tags = readLocalTags(
      _u8(<int>[1, 2, 3, 4, 5]),
      fallbackName: r'C:\Music\夜曲.mp3',
    );
    expect(tags.title, '夜曲');
    expect(tags.artist, '');
    expect(tags.album, '');
  });

  test('截断的 ID3 数据不崩溃并回退文件名', () {
    final complete = _id3Tag(<List<int>>[
      _id3Frame('TIT2', _id3Text('完整标题', encoding: 3)),
      _id3Frame('TPE1', _id3Text('完整歌手', encoding: 3)),
    ]);

    final truncated = Uint8List.sublistView(complete, 0, complete.length - 3);
    expect(
      () => readLocalTags(truncated, fallbackName: 'truncated.mp3'),
      returnsNormally,
    );
    // 截断发生在后续帧时，前面已完整读出的标签仍可返回。
    expect(
      readLocalTags(truncated, fallbackName: 'truncated.mp3').title,
      '完整标题',
    );

    // 截断发生在第一帧正文中时，应安全回退。
    final midFrame = Uint8List.sublistView(complete, 0, 23);
    expect(
      readLocalTags(midFrame, fallbackName: 'truncated.mp3').title,
      'truncated',
    );

    final frameHeaderOnly = Uint8List.sublistView(complete, 0, 14);
    expect(
      readLocalTags(frameHeaderOnly, fallbackName: 'cut.mp3').title,
      'cut',
    );
  });

  test('截断的 FLAC 数据不崩溃并回退文件名', () {
    final complete = _flacTag(<String>['TITLE=晴天']);
    final truncated = Uint8List.sublistView(complete, 0, 20);

    expect(
      () => readLocalTags(truncated, fallbackName: 'cut.flac'),
      returnsNormally,
    );
    expect(
      readLocalTags(truncated, fallbackName: 'cut.flac').title,
      'cut',
    );
  });
}
