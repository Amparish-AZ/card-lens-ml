import 'dart:convert';
import 'dart:math' as math;

import 'package:tflite_flutter/tflite_flutter.dart';

import 'card_parser.dart';
import 'ocr_service.dart';

/// Stage 2: a tiny offline TensorFlow Lite classifier for OCR text lines.
class SmartBusinessCardParser {
  static const _labels = [
    'name',
    'title',
    'company',
    'email',
    'phone',
    'website',
    'address',
    'other',
  ];

  static Interpreter? _cachedInterpreter;
  static bool _initAttempted = false;

  static Future<Interpreter?> _getInterpreter() async {
    if (_cachedInterpreter != null) return _cachedInterpreter;
    if (_initAttempted && _cachedInterpreter == null) return null;
    _initAttempted = true;
    try {
      _cachedInterpreter = await Interpreter.fromAsset(
        'assets/models/card_field_classifier.tflite',
      );
    } catch (_) {
      _cachedInterpreter = null;
    }
    return _cachedInterpreter;
  }

  static List<OcrLine> sortLinesAdaptively(List<OcrLine> lines) {
    if (lines.length <= 1) return lines;
    final avgHeight = lines.map((e) => e.height).reduce((a, b) => a + b) / lines.length;
    final tolerance = math.max(6.0, avgHeight * 0.45);
    final sorted = List<OcrLine>.from(lines);
    sorted.sort((a, b) {
      if ((a.top - b.top).abs() < tolerance) {
        return a.left.compareTo(b.left);
      }
      return a.top.compareTo(b.top);
    });
    return sorted;
  }

  static Future<BusinessCardData> parse(
    String rawText, {
    List<OcrLine> layout = const [],
  }) async {
    final fallback = BusinessCardParser.parse(rawText);
    final sortedLayout = sortLinesAdaptively(layout);
    final spatial = _spatialCandidates(sortedLayout, fallback: fallback);
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((e) => e.length > 1)
        .toList();
    if (lines.isEmpty) return fallback;

    try {
      final interpreter = await _getInterpreter();
      if (interpreter != null) {
        final selected = <String, (String, double)>{};
        for (var i = 0; i < lines.length; i++) {
          final input = [_features(lines[i], i, lines.length)];
          final output = [List<double>.filled(_labels.length, 0)];
          interpreter.run(input, output);
          final scores = output.first;
          var best = 0;
          for (var j = 1; j < scores.length; j++) {
            if (scores[j] > scores[best]) best = j;
          }
          final current = selected[_labels[best]];
          if (current == null || scores[best] > current.$2) {
            selected[_labels[best]] = (lines[i], scores[best]);
          }
        }
        String value(
          String label,
          String safeFallback, {
          bool Function(String)? validate,
          double minimumConfidence = .70,
        }) {
          if (safeFallback.isNotEmpty) return safeFallback;
          final candidate = selected[label];
          if (candidate == null || candidate.$2 < minimumConfidence) return '';
          return validate == null || validate(candidate.$1) ? candidate.$1 : '';
        }

        final parsedCompany =
            spatial['company'] ??
            value(
              'company',
              fallback.company,
              validate: _validCompany,
              minimumConfidence: .75,
            );
        final domainCompany = _companyFromContacts(rawText);
        final resolvedCompany =
            domainCompany.isNotEmpty &&
                (parsedCompany.isEmpty ||
                    parsedCompany == (spatial['name'] ?? fallback.name) ||
                    _genericDescriptor(parsedCompany))
            ? domainCompany
            : parsedCompany;

        final inferredAddress = selected['address']?.$1 ?? '';
        return BusinessCardData(
          name:
              spatial['name'] ??
              value(
                'name',
                fallback.name,
                validate: _validName,
                minimumConfidence: .75,
              ),
          jobTitle: value(
            'title',
            fallback.jobTitle,
            validate: BusinessCardParser.titles.hasMatch,
            minimumConfidence: .70,
          ),
          company: resolvedCompany,
          email: fallback.email,
          phone: fallback.phone,
          website: fallback.website,
          address: fallback.address.isNotEmpty
              ? fallback.address
              : (_validAddress(inferredAddress) ? inferredAddress : ''),
          stall: fallback.stall,
          notes: fallback.notes,
          rawText: rawText,
          additionalEmails: fallback.additionalEmails,
          additionalPhones: fallback.additionalPhones,
          additionalWebsites: fallback.additionalWebsites,
          otherFields: fallback.otherFields
              .where(
                (line) => line != spatial['name'] && line != spatial['company'],
              )
              .toList(),
        );
      }
    } catch (_) {
      // Fall through to spatial fallback below
    }

    final parsedCompany = spatial['company'] ?? fallback.company;
    final domainCompany = _companyFromContacts(rawText);
    final resolvedCompany =
        domainCompany.isNotEmpty &&
            (parsedCompany.isEmpty ||
                parsedCompany == (spatial['name'] ?? fallback.name) ||
                _genericDescriptor(parsedCompany))
        ? domainCompany
        : parsedCompany;
    return BusinessCardData(
      name: spatial['name'] ?? fallback.name,
      jobTitle: fallback.jobTitle,
      company: resolvedCompany,
      email: fallback.email,
      phone: fallback.phone,
      website: fallback.website,
      address: fallback.address,
      stall: fallback.stall,
      notes: fallback.notes,
      rawText: rawText,
      additionalEmails: fallback.additionalEmails,
      additionalPhones: fallback.additionalPhones,
      additionalWebsites: fallback.additionalWebsites,
      otherFields: fallback.otherFields
          .where(
            (line) => line != spatial['name'] && line != spatial['company'],
          )
          .toList(),
    );
  }

  static Map<String, String> _spatialCandidates(
    List<OcrLine> lines, {
    BusinessCardData? fallback,
  }) {
    if (lines.isEmpty) return const {};
    bool contact(String text) =>
        BusinessCardParser.email.hasMatch(text) ||
        BusinessCardParser.isPhoneLine(text) ||
        BusinessCardParser.web.hasMatch(text) ||
        BusinessCardParser.addresses.hasMatch(text) ||
        BusinessCardParser.titles.hasMatch(text) ||
        BusinessCardParser.stallPattern.hasMatch(text) ||
        BusinessCardParser.productTagline.hasMatch(text);

    final semantic = lines.where((line) => !contact(line.text)).toList();
    final explicitCompanies = semantic
        .where((line) => BusinessCardParser.companies.hasMatch(line.text))
        .toList();
    var company = explicitCompanies
        .where((line) => !_genericDescriptor(line.text))
        .firstOrNull;

    bool personLike(OcrLine line) {
      final words = line.text.trim().split(RegExp(r'\s+'));
      return line != company &&
          (words.isNotEmpty ||
              (line.text.contains('.') &&
                  RegExp(r'[A-Za-z]').allMatches(line.text).length >= 4)) &&
          words.length <= 5 &&
          RegExp(r"^[A-Za-z .\-'’]+$").hasMatch(line.text) &&
          !BusinessCardParser.companies.hasMatch(line.text) &&
          !BusinessCardParser.productTagline.hasMatch(line.text);
    }

    // A person's name is normally the closest name-shaped line immediately
    // above their job title.
    final titleLines = lines
        .where((line) => BusinessCardParser.titles.hasMatch(line.text))
        .toList();
    OcrLine? person;
    double closestGap = double.infinity;
    for (final title in titleLines) {
      for (final candidate in semantic.where(personLike)) {
        final gap = title.top - (candidate.top + candidate.height);
        if (gap >= -title.height && gap < closestGap) {
          closestGap = gap;
          person = candidate;
        }
      }
    }

    if (person == null) {
      final candidates = semantic.where(personLike).toList();
      double score(OcrLine line) {
        var result = line.height;
        if (line.text.contains('.')) result += 12;
        final index = lines.indexOf(line);
        if (index + 1 < lines.length &&
            (BusinessCardParser.isPhoneLine(lines[index + 1].text) ||
                BusinessCardParser.titles.hasMatch(lines[index + 1].text))) {
          result += 30;
        }
        if (BusinessCardParser.productTagline.hasMatch(line.text)) {
          result -= 80;
        }
        return result;
      }

      candidates.sort((a, b) => score(b).compareTo(score(a)));
      person = candidates.firstOrNull;
    }

    // If fallback already found a clean name, respect that
    if (fallback != null && fallback.name.isNotEmpty) {
      final match = lines.where((l) => l.text.trim() == fallback.name.trim()).firstOrNull;
      if (match != null) person = match;
    }

    if (company != null && _genericDescriptor(company.text)) {
      final brand = semantic.where((line) {
        if (line == person || line == company) return false;
        final letters = RegExp(r'[A-Za-z]').allMatches(line.text).length;
        final upper = RegExp(r'[A-Z]').allMatches(line.text).length;
        return letters >= 3 &&
            line.text.length <= 35 &&
            (upper / letters >= .4 || line.height >= 16) &&
            !_genericDescriptor(line.text) &&
            !BusinessCardParser.productTagline.hasMatch(line.text);
      }).firstOrNull;
      company = brand;
    }

    company ??=
        (semantic.where((line) {
              if (line == person) return false;
              final letters = RegExp(r'[A-Za-z]').allMatches(line.text).length;
              final upper = RegExp(r'[A-Z]').allMatches(line.text).length;
              return letters >= 3 &&
                  line.text.length <= 45 &&
                  !_genericDescriptor(line.text) &&
                  !BusinessCardParser.productTagline.hasMatch(line.text) &&
                  (BusinessCardParser.companies.hasMatch(line.text) ||
                      upper / letters >= .4 ||
                      line.height >= 16);
            }).toList()..sort((a, b) {
              final topOrder = a.top.compareTo(b.top);
              if ((a.height - b.height).abs() < 3) return topOrder;
              return b.height.compareTo(a.height);
            }))
            .firstOrNull;

    final resolvedCompany = (fallback != null &&
            fallback.company.isNotEmpty &&
            !_genericDescriptor(fallback.company))
        ? fallback.company
        : (company != null && !_genericDescriptor(company.text)
            ? company.text
            : null);

    final result = <String, String>{};
    if (person != null) {
      result['name'] = person.text;
    }
    if (resolvedCompany != null) {
      result['company'] = resolvedCompany;
    }
    return result;
  }

  static bool _validAddress(String line) {
    if (line.trim().isEmpty ||
        BusinessCardParser.email.hasMatch(line) ||
        BusinessCardParser.isPhoneLine(line) ||
        BusinessCardParser.web.hasMatch(line) ||
        BusinessCardParser.stallPattern.hasMatch(line) ||
        BusinessCardParser.productTagline.hasMatch(line)) {
      return false;
    }
    return BusinessCardParser.addresses.hasMatch(line) ||
        (RegExp(r'^\d+\s+[A-Za-z]').hasMatch(line) && line.contains(','));
  }

  static bool _genericDescriptor(String value) =>
      BusinessCardParser.isGenericTagline(value.trim());

  static String _companyFromContacts(String text) {
    final hosts = <String>[
      ...RegExp(
        r'[A-Z0-9._%+\-]+@([A-Z0-9.\-]+)',
        caseSensitive: false,
      ).allMatches(text).map((match) => match.group(1)!),
      ...BusinessCardParser.web
          .allMatches(text.replaceAll(BusinessCardParser.email, ''))
          .map((match) => match.group(0)!),
    ];
    const publicProviders = {
      'gmail',
      'yahoo',
      'outlook',
      'hotmail',
      'proton',
      'www',
      'icloud',
      'zoho',
      'rediffmail',
      'mail',
      'ymail',
      'example',
      'sample',
      'test',
      'temp',
      'demo',
      'domain',
      'placeholder',
    };
    for (final rawHost in hosts) {
      final host = rawHost
          .replaceFirst(
            RegExp(r'^(?:https?://)?www\.', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'\s+'), '');
      if (host.isEmpty) continue;
      final parts = host.split('.');
      final brand = parts.length > 2 &&
              (parts[parts.length - 2] == 'co' ||
                  parts[parts.length - 2] == 'com' ||
                  parts[parts.length - 2] == 'org')
          ? parts[parts.length - 3]
          : parts.first;
      if (brand.length < 3 || publicProviders.contains(brand.toLowerCase())) {
        continue;
      }

      // Clean domain name into formatted words
      return brand
          .replaceAllMapped(
            RegExp(
              r'(global|construction|consulting|solutions|interiors?|associates?|ventures?|enterprises?|tech|technology|technologies|engineering|systems|packaging|plastics|fabrics|textiles|motors|industries|trading|logistics|property|decor|design|media|info)',
              caseSensitive: false,
            ),
            (match) => ' ${match[0]} ',
          )
          .replaceAllMapped(
            RegExp(r'[A-Z]'),
            (m) => ' ${m[0]}',
          )
          .replaceAll(RegExp(r'[-_]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toUpperCase();
    }
    return '';
  }

  static bool _validName(String line) {
    final words = line.trim().split(RegExp(r'\s+'));
    return words.isNotEmpty &&
        words.length <= 5 &&
        RegExp(r"^[A-Za-z .\-'’]+$").hasMatch(line) &&
        !BusinessCardParser.companies.hasMatch(line) &&
        !BusinessCardParser.productTagline.hasMatch(line) &&
        !BusinessCardParser.titles.hasMatch(line);
  }

  static bool _validCompany(String line) {
    if (BusinessCardParser.email.hasMatch(line) ||
        BusinessCardParser.isPhoneLine(line) ||
        BusinessCardParser.web.hasMatch(line) ||
        BusinessCardParser.productTagline.hasMatch(line) ||
        BusinessCardParser.titles.hasMatch(line)) {
      return false;
    }
    final letters = RegExp(r'[A-Za-z]').allMatches(line).length;
    final upper = RegExp(r'[A-Z]').allMatches(line).length;
    return BusinessCardParser.companies.hasMatch(line) ||
        (letters >= 3 && upper / letters >= .55);
  }

  static List<double> _features(String line, int index, int count) {
    final output = List<double>.filled(128, 0);
    final lower = line.toLowerCase().trim();
    final grams = <String>[
      ...lower.split(''),
      for (var i = 0; i + 1 < lower.length; i++) lower.substring(i, i + 2),
    ];
    for (final gram in grams) {
      output[_fnv1a(gram) % 96]++;
    }
    if (grams.isNotEmpty) {
      for (var i = 0; i < 96; i++) {
        output[i] /= grams.length;
      }
    }
    final letters = RegExp(r'[A-Za-z]').allMatches(line).length;
    final digits = RegExp(r'\d').allMatches(line).length;
    final upper = RegExp(r'[A-Z]').allMatches(line).length;
    final length = line.length.clamp(1, 100);
    final words = line
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final emailSignal = BusinessCardParser.email.hasMatch(line);
    final phoneSignal = BusinessCardParser.phone.hasMatch(line);
    final webSignal = RegExp(
      r'(?:www\.|https?://|\.[a-z]{2,})',
      caseSensitive: false,
    ).hasMatch(line);
    final addressSignal = RegExp(
      r'\b(street|road|avenue|lane|suite|sector|phase|park|estate)\b|\b\d{5,6}\b',
      caseSensitive: false,
    ).hasMatch(line);
    final titleSignal = BusinessCardParser.titles.hasMatch(line);
    final companySignal = BusinessCardParser.companies.hasMatch(line);
    output.setRange(
      96,
      102,
      [
        emailSignal,
        phoneSignal,
        webSignal,
        addressSignal,
        titleSignal,
        companySignal,
      ].map((e) => e ? 1.0 : 0.0),
    );
    output[102] = letters / length;
    output[103] = digits / length;
    output[104] = upper / (letters == 0 ? 1 : letters);
    output[105] = (words.length / 8).clamp(0, 1);
    output[106] = (length / 100).clamp(0, 1);
    output[107] = index / (count <= 1 ? 1 : count - 1);
    output[108] = (RegExp(',').allMatches(line).length / 3).clamp(0, 1);
    output[109] = (RegExp(r'\.').allMatches(line).length / 3).clamp(0, 1);
    output[110] = line.contains('-') ? 1 : 0;
    output[111] = line.contains('+') ? 1 : 0;
    output[112] = line.contains(':') ? 1 : 0;
    output[113] = line.contains('&') ? 1 : 0;
    output[114] = letters > 2 && upper == letters ? 1 : 0;
    output[115] =
        words.where((w) => RegExp(r'^[A-Z]').hasMatch(w)).length /
        (words.isEmpty ? 1 : words.length);
    output[116] = RegExp(r'^\d').hasMatch(line) ? 1 : 0;
    output[117] = RegExp(r'\b\d{5,6}\b').hasMatch(line) ? 1 : 0;
    output[118] = lower.contains('www.') || lower.contains('http') ? 1 : 0;
    output[119] =
        RegExp(
          r'(gmail\.com|outlook\.com|proton\.me|yahoo\.com|company\.co\.in|business\.com|studio\.design|global\.io)',
        ).hasMatch(lower)
        ? 1
        : 0;
    output[120] = companySignal ? 1 : 0;
    output[121] = RegExp(r'^\d+\s+[A-Za-z]').hasMatch(line) ? 1 : 0;
    output[122] = line.contains('(') ? 1 : 0;
    output[123] =
        words.fold<int>(0, (sum, word) => sum + word.length) /
        ((words.isEmpty ? 1 : words.length) * 15);
    output[124] = ((line.split(' ').length - 1) / 8).clamp(0, 1);
    output[125] = line.contains('@') ? 1 : 0;
    output[126] = line.contains('/') ? 1 : 0;
    output[127] = 1;
    return output;
  }

  static int _fnv1a(String value) {
    var hash = 2166136261;
    for (final byte in utf8.encode(value)) {
      hash = ((hash ^ byte) * 16777619) & 0xffffffff;
    }
    return hash;
  }
}
