class NovelChapter {
  const NovelChapter({
    required this.title,
    required this.url,
    required this.content,
    required this.order,
  });

  final String title;
  final String url;
  final String content;
  final int order;

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'content': content,
    'order': order,
  };

  factory NovelChapter.fromJson(Map<String, dynamic> json) {
    return NovelChapter(
      title: (json['title'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }
}

class NovelBook {
  const NovelBook({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.importedAt,
    required this.chapters,
    this.lastReadChapterIndex = 0,
  });

  final String id;
  final String title;
  final String sourceUrl;
  final DateTime importedAt;
  final List<NovelChapter> chapters;
  final int lastReadChapterIndex;

  String get sourceLabel {
    final source = Uri.tryParse(sourceUrl);
    return switch (source?.scheme) {
      'http' || 'https' => source!.host,
      'sample' => 'Sample book',
      'epub' || 'local-epub' => 'EPUB file',
      'pdf' || 'local-pdf' => 'PDF file',
      _ => 'Local file',
    };
  }

  NovelBook copyWith({
    String? id,
    String? title,
    String? sourceUrl,
    DateTime? importedAt,
    List<NovelChapter>? chapters,
    int? lastReadChapterIndex,
  }) {
    return NovelBook(
      id: id ?? this.id,
      title: title ?? this.title,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      importedAt: importedAt ?? this.importedAt,
      chapters: chapters ?? this.chapters,
      lastReadChapterIndex: lastReadChapterIndex ?? this.lastReadChapterIndex,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'sourceUrl': sourceUrl,
    'importedAt': importedAt.toIso8601String(),
    'lastReadChapterIndex': lastReadChapterIndex,
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
  };

  factory NovelBook.fromJson(Map<String, dynamic> json) {
    final chapters = (json['chapters'] as List<dynamic>? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(NovelChapter.fromJson)
        .toList();

    return NovelBook(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      sourceUrl: (json['sourceUrl'] ?? '').toString(),
      importedAt:
          DateTime.tryParse((json['importedAt'] ?? '').toString()) ??
          DateTime.now(),
      lastReadChapterIndex:
          (json['lastReadChapterIndex'] as num?)?.toInt() ?? 0,
      chapters: chapters,
    );
  }
}
