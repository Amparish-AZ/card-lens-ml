import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SavedCard {
  const SavedCard({
    required this.id,
    required this.createdAt,
    required this.imagePath,
    required this.fields,
  });

  final String id;
  final DateTime createdAt;
  final String imagePath;
  final Map<String, String> fields;

  String get title => fields['Full name']?.trim().isNotEmpty == true
      ? fields['Full name']!.trim()
      : (fields['Company']?.trim().isNotEmpty == true
            ? fields['Company']!.trim()
            : 'Business card');

  String get shareText => fields.entries
      .where((entry) => entry.value.trim().isNotEmpty)
      .map((entry) => '${entry.key}: ${entry.value.trim()}')
      .join('\n');

  String toVCard() {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCARD');
    buffer.writeln('VERSION:3.0');
    final name = fields['Full name']?.trim() ?? '';
    buffer.writeln('FN:$name');
    final nameParts = name.split(' ');
    if (nameParts.length > 1) {
      buffer.writeln('N:${nameParts.last};${nameParts.sublist(0, nameParts.length - 1).join(' ')};;;');
    } else {
      buffer.writeln('N:$name;;;;');
    }
    final company = fields['Company']?.trim() ?? '';
    if (company.isNotEmpty) buffer.writeln('ORG:$company');
    final title = fields['Job title']?.trim() ?? '';
    if (title.isNotEmpty) buffer.writeln('TITLE:$title');

    for (final entry in fields.entries) {
      if (entry.key.startsWith('Phone') && entry.value.trim().isNotEmpty) {
        final phoneVal = entry.value.trim();
        final isCell = phoneVal.toLowerCase().contains('whatsapp') || phoneVal.startsWith('+');
        buffer.writeln('TEL;TYPE=${isCell ? 'CELL' : 'WORK'}:$phoneVal');
      }
    }

    for (final entry in fields.entries) {
      if (entry.key.startsWith('Email') && entry.value.trim().isNotEmpty) {
        buffer.writeln('EMAIL;TYPE=INTERNET:${entry.value.trim()}');
      }
    }

    for (final entry in fields.entries) {
      if (entry.key.startsWith('Website') && entry.value.trim().isNotEmpty) {
        buffer.writeln('URL:${entry.value.trim()}');
      }
    }

    final address = fields['Address']?.trim() ?? '';
    if (address.isNotEmpty) {
      buffer.writeln('ADR;TYPE=WORK:;;$address;;;;');
    }

    final noteLines = <String>[];
    final stall = fields['Stall / Booth']?.trim() ?? '';
    if (stall.isNotEmpty) noteLines.add('Stall/Booth: $stall');
    final notes = fields['Notes']?.trim() ?? '';
    if (notes.isNotEmpty) noteLines.add(notes);
    if (noteLines.isNotEmpty) {
      buffer.writeln('NOTE:${noteLines.join('\\n')}');
    }

    buffer.writeln('END:VCARD');
    return buffer.toString();
  }

  List<String> toCsvRow() {
    final name = fields['Full name']?.trim() ?? '';
    final jobTitle = fields['Job title']?.trim() ?? '';
    final company = fields['Company']?.trim() ?? '';

    String primaryPhone = '';
    final otherPhones = <String>[];
    for (final entry in fields.entries) {
      if (entry.key.startsWith('Phone') && entry.value.trim().isNotEmpty) {
        if (primaryPhone.isEmpty) {
          primaryPhone = entry.value.trim();
        } else {
          otherPhones.add(entry.value.trim());
        }
      }
    }

    String whatsAppUrl = '';
    if (primaryPhone.isNotEmpty) {
      var digits = primaryPhone.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 10) digits = '91$digits';
      if (digits.length >= 10) whatsAppUrl = 'https://wa.me/$digits';
    }

    final email = fields['Email']?.trim() ?? '';
    final website = fields['Website']?.trim() ?? '';
    final address = fields['Address']?.trim() ?? '';
    String mapsUrl = '';
    if (address.isNotEmpty) {
      mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}';
    }

    final stall = fields['Stall / Booth']?.trim() ?? '';
    final notes = fields['Notes']?.trim() ?? '';
    final dateStr =
        '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

    return [
      name,
      jobTitle,
      company,
      primaryPhone,
      otherPhones.join('; '),
      whatsAppUrl,
      email,
      website,
      address,
      mapsUrl,
      stall,
      notes,
      dateStr,
    ];
  }

  Map<String, Object> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'imagePath': imagePath,
    'fields': fields,
  };

  factory SavedCard.fromJson(Map<String, dynamic> json) => SavedCard(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    imagePath: json['imagePath'] as String,
    fields: Map<String, String>.from(json['fields'] as Map),
  );
}

class SavedCardStore {
  static Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}cards');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<File> _index() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}cards.json');
  }

  static Future<List<SavedCard>> load() async {
    try {
      final index = await _index();
      if (!await index.exists()) return [];
      final decoded = jsonDecode(await index.readAsString()) as List<dynamic>;
      final cards = decoded
          .map((value) => SavedCard.fromJson(value as Map<String, dynamic>))
          .toList();
      cards.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return cards;
    } catch (_) {
      return [];
    }
  }

  static Future<SavedCard> save({
    required String sourceImagePath,
    required Map<String, String> fields,
  }) async {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final directory = await _directory();
    final extension = sourceImagePath.toLowerCase().endsWith('.png')
        ? 'png'
        : 'jpg';
    final image = await File(sourceImagePath)
        .copy('${directory.path}${Platform.pathSeparator}$id.$extension');
    final card = SavedCard(
      id: id,
      createdAt: now,
      imagePath: image.path,
      fields: Map<String, String>.from(fields),
    );
    final cards = await load();
    cards.insert(0, card);
    await _write(cards);
    return card;
  }

  static Future<void> delete(SavedCard card) async {
    final cards = await load();
    cards.removeWhere((item) => item.id == card.id);
    final image = File(card.imagePath);
    if (await image.exists()) await image.delete();
    await _write(cards);
  }

  static Future<void> _write(List<SavedCard> cards) async {
    final index = await _index();
    await index.writeAsString(
      jsonEncode(cards.map((card) => card.toJson()).toList()),
      flush: true,
    );
  }

  static String generateCsv(List<SavedCard> cards) {
    final buffer = StringBuffer();
    // UTF-8 BOM for Microsoft Excel compatibility with international characters
    buffer.write('\uFEFF');
    final headers = [
      'Full Name',
      'Job Title',
      'Company',
      'Primary Phone',
      'Additional Phones',
      'WhatsApp Direct Link',
      'Email',
      'Website',
      'Address',
      'Google Maps Link',
      'Stall / Booth',
      'Notes',
      'Scanned Date',
    ];
    buffer.writeln(headers.map(_csvEscape).join(','));
    for (final card in cards) {
      buffer.writeln(card.toCsvRow().map(_csvEscape).join(','));
    }
    return buffer.toString();
  }

  static String _csvEscape(String val) {
    if (val.contains(',') || val.contains('"') || val.contains('\n') || val.contains('\r')) {
      return '"${val.replaceAll('"', '""')}"';
    }
    return val;
  }

  static Future<File> writeCsvFile(List<SavedCard> cards, {String? filename}) async {
    final tempDir = await getTemporaryDirectory();
    final name = filename ?? 'expo_contacts_${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${tempDir.path}/$name.csv');
    await file.writeAsString(generateCsv(cards), encoding: utf8);
    return file;
  }
}
