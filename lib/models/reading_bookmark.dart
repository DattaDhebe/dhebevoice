import 'dart:convert';

import 'package:characters/characters.dart';

class ReadingBookmark {
  static bool validNote(String value) =>
      value.length <= 16000 && value.characters.length <= 1000;
  const ReadingBookmark({
    required this.chapterUrl,
    required this.chapterTitle,
    required this.position,
    required this.paragraphIndex,
    required this.excerpt,
    required this.createdAt,
    this.note = '',
  });

  final String chapterUrl;
  final String chapterTitle;
  final int position;
  final int paragraphIndex;
  final String excerpt;
  final DateTime createdAt;
  final String note;

  String get id => jsonEncode([chapterUrl, position]);

  ReadingBookmark copyWith({String? note, DateTime? createdAt}) =>
      ReadingBookmark(
        chapterUrl: chapterUrl,
        chapterTitle: chapterTitle,
        position: position,
        paragraphIndex: paragraphIndex,
        excerpt: excerpt,
        createdAt: createdAt ?? this.createdAt,
        note: note ?? this.note,
      );

  Map<String, Object> toJson() => {
    'chapterUrl': chapterUrl,
    'chapterTitle': chapterTitle,
    'position': position,
    'paragraphIndex': paragraphIndex,
    'excerpt': excerpt,
    'createdAt': createdAt.toIso8601String(),
    'note': note,
  };

  factory ReadingBookmark.fromJson(Map<String, dynamic> json) {
    final date = json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt'] as String)
        : null;
    if (json['chapterUrl'] is! String ||
        (json['chapterUrl'] as String).isEmpty ||
        json['chapterTitle'] is! String ||
        json['position'] is! int ||
        (json['position'] as int) < 0 ||
        json['paragraphIndex'] is! int ||
        (json['paragraphIndex'] as int) < 0 ||
        json['excerpt'] is! String ||
        json['note'] is! String ||
        !validNote(json['note'] as String) ||
        date == null) {
      throw const FormatException('Saved bookmarks could not be read.');
    }
    return ReadingBookmark(
      chapterUrl: json['chapterUrl'] as String,
      chapterTitle: json['chapterTitle'] as String,
      position: json['position'] as int,
      paragraphIndex: json['paragraphIndex'] as int,
      excerpt: json['excerpt'] as String,
      createdAt: date,
      note: json['note'] as String,
    );
  }
}
