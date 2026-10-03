class BusinessCardData {
  const BusinessCardData({
    this.name = '',
    this.jobTitle = '',
    this.company = '',
    this.email = '',
    this.phone = '',
    this.website = '',
    this.address = '',
    this.stall = '',
    this.notes = '',
    this.rawText = '',
    this.additionalEmails = const [],
    this.additionalPhones = const [],
    this.additionalWebsites = const [],
    this.otherFields = const [],
  });
  final String name, jobTitle, company, email, phone, website, address, stall, notes, rawText;
  final List<String> additionalEmails;
  final List<String> additionalPhones;
  final List<String> additionalWebsites;
  final List<String> otherFields;

  Map<String, Object> toSchemaInstance() => {
    'name': name,
    'job_title': jobTitle,
    'company_name': company,
    'emails': [email, ...additionalEmails].where((e) => e.isNotEmpty).toList(),
    'phone_numbers': [
      phone,
      ...additionalPhones,
    ].where((e) => e.isNotEmpty).toList(),
    'websites': [
      website,
      ...additionalWebsites,
    ].where((e) => e.isNotEmpty).toList(),
    'address': address,
    if (stall.isNotEmpty) 'stall': stall,
    if (notes.isNotEmpty) 'notes': notes,
    'other_detected_fields': otherFields,
  };

  static BusinessCardData merge(BusinessCardData front, BusinessCardData back) {
    final mergedName = front.name.trim().isNotEmpty ? front.name : back.name;
    final mergedJobTitle = front.jobTitle.trim().isNotEmpty ? front.jobTitle : back.jobTitle;
    final mergedCompany = front.company.trim().isNotEmpty ? front.company : back.company;

    // Deduplicate emails
    final allEmails = <String>[
      if (front.email.isNotEmpty) front.email,
      ...front.additionalEmails,
      if (back.email.isNotEmpty) back.email,
      ...back.additionalEmails,
    ];
    final uniqueEmails = <String>[];
    for (final em in allEmails) {
      final clean = em.trim();
      if (clean.isNotEmpty && !uniqueEmails.any((e) => e.toLowerCase() == clean.toLowerCase())) {
        uniqueEmails.add(clean);
      }
    }

    // Deduplicate phones
    final allPhones = <String>[
      if (front.phone.isNotEmpty) front.phone,
      ...front.additionalPhones,
      if (back.phone.isNotEmpty) back.phone,
      ...back.additionalPhones,
    ];
    final uniquePhones = <String>[];
    for (final ph in allPhones) {
      final clean = ph.trim();
      final digits = clean.replaceAll(RegExp(r'\D'), '');
      if (clean.isNotEmpty && !uniquePhones.any((p) => p.replaceAll(RegExp(r'\D'), '') == digits)) {
        uniquePhones.add(clean);
      }
    }

    // Deduplicate websites
    final allWebsites = <String>[
      if (front.website.isNotEmpty) front.website,
      ...front.additionalWebsites,
      if (back.website.isNotEmpty) back.website,
      ...back.additionalWebsites,
    ];
    final uniqueWebsites = <String>[];
    for (final wb in allWebsites) {
      final clean = wb.trim();
      if (clean.isNotEmpty && !uniqueWebsites.any((w) => w.toLowerCase() == clean.toLowerCase())) {
        uniqueWebsites.add(clean);
      }
    }

    // Combine addresses
    String mergedAddress = front.address.trim();
    if (back.address.trim().isNotEmpty) {
      if (mergedAddress.isEmpty) {
        mergedAddress = back.address.trim();
      } else if (!mergedAddress.toLowerCase().contains(back.address.trim().toLowerCase())) {
        mergedAddress = '$mergedAddress (Back: ${back.address.trim()})';
      }
    }

    // Stall / Booth
    final mergedStall = front.stall.trim().isNotEmpty ? front.stall : back.stall;

    // Combine notes / services catalog
    final noteParts = <String>[];
    if (front.notes.trim().isNotEmpty) noteParts.add(front.notes.trim());
    if (back.notes.trim().isNotEmpty && !noteParts.contains(back.notes.trim())) {
      noteParts.add(back.notes.trim());
    }
    if (back.otherFields.isNotEmpty) {
      final extraBack = back.otherFields.where((f) => f.length > 3).join(', ');
      if (extraBack.isNotEmpty && !noteParts.any((n) => n.contains(extraBack))) {
        noteParts.add('Back: $extraBack');
      }
    }

    return BusinessCardData(
      name: mergedName,
      jobTitle: mergedJobTitle,
      company: mergedCompany,
      email: uniqueEmails.firstOrNull ?? '',
      additionalEmails: uniqueEmails.skip(1).toList(),
      phone: uniquePhones.firstOrNull ?? '',
      additionalPhones: uniquePhones.skip(1).toList(),
      website: uniqueWebsites.firstOrNull ?? '',
      additionalWebsites: uniqueWebsites.skip(1).toList(),
      address: mergedAddress,
      stall: mergedStall,
      notes: noteParts.join('\n'),
      rawText: '--- FRONT ---\n${front.rawText}\n--- BACK ---\n${back.rawText}',
      otherFields: {
        ...front.otherFields,
        ...back.otherFields,
      }.toList(),
    );
  }
}

class BusinessCardParser {
  static final email = RegExp(
    r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );
  static final phone = RegExp(r'(?:\(?\+?\d+\)?[\d \t().\-]{5,}\d|\+?\d[\d \t().\-]{6,}\d)');
  static final web = RegExp(
    r'(?:https?://)?(?:www\.)?[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.(?:com|in|net|org|co|io|biz|info|me|ai|dev|app|design|tech|store|online|global|ltd|trade|industrial|group|solutions|ae|uk|us|de|sg|ca|au|co\.in|org\.in|com\.sg|co\.uk)(?:/[^\s]*)?',
    caseSensitive: false,
  );
  static final titles = RegExp(
    r'\b(founder|co-founder|owner|proprietor|prop\.?|partner|managing partner|director|managing director|md|executive director|officer|chief executive officer|ceo|cto|cfo|coo|cmo|president|vice president|vp|general manager|gm|manager|head|lead|lead engineer|engineer|senior engineer|developer|designer|consultant|advisor|architect|attorney|advocate|doctor|dr\.?|professor|prof\.?|executive|sales executive|marketing executive|sales manager|marketing manager|export manager|bdm|business development|commercial manager|technical director|representative|operations manager)\b',
    caseSensitive: false,
  );
  static final companies = RegExp(
    r'\b(inc\.?|llc|llp|ltd\.?|limited|corp\.?|corporation|company|co\.?|solutions|technologies|technology|tech|studio|group|associates|enterprises|agency|services|pvt\.?|private limited|builders?|construction|contractors?|interiors?|accessories|lifts?|elevators?|escalators?|advocates?|ventures?|industries|consulting|events?|entertainment|medical|property|designs?|decor|media|aids|systems|logistics|holdings|trading|exports?|impex|packaging|plastics|fabrics|textiles|engineering|hardware|international|electronics|chemicals|pharma|motors|automotive|instruments|tools|sweets?|bakes?|bakery|caterers?|catering|palagaram|restaurant|foods?|kitchen|hotel|cafe|snacks|tiffin|mess|stores?|mart|traders?|agencies|agency|emporium|bazaar|jewellers?|silks?|fashions?|boutique|tailors?|garments|works|press|printers?|creations?|loan|loans|finance|financial|capital|credit|wealth|investments|insurance|finserv|advisory|banking|funds|fintech|realty|properties)\b',
    caseSensitive: false,
  );
  static final addresses = RegExp(
    r'\b(street|st\.?|road|rd\.?|salai|pathai|cross|main|avenue|ave\.?|lane|ln\.?|drive|dr\.?|boulevard|blvd\.?|highway|hwy|suite|ste\.?|floor|fl\.?|building|bldg\.?|apartment|apt\.?|flats?|tower|block|complex|shop|sector|phase|nagar|colony|estate|park|city|state|zip|pin|postal|po box|p\.o\.\s*box|midc|gic|area|industrial|dubai|chennai|bangalore|bengaluru|mumbai|delhi|kolkata|hyderabad|pune|ahmedabad|coimbatore|vadapalani|t\.?\s*nagar|anna\s+nagar|opp\.?|opposite|near|behind|beside)\b|\b\d{3}\s?\d{3}\b|\b(?:chennai|mumbai|delhi|kolkata|bangalore|hyderabad|pune)\s*[-–]?\s*\d{1,3}\b|\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b',
    caseSensitive: false,
  );
  static final stallPattern = RegExp(
    r'\b(?:stall|booth|hall)\s*(?:no\.?|#)?\s*[:\-]?\s*([A-Za-z0-9\-–/]+(?:\s*,\s*(?:stall|booth|hall)\s*(?:no\.?|#)?\s*[:\-]?\s*[A-Za-z0-9\-–/]+)?)\b|\bhall\s*(?:no\.?|#)?\s*[:\-]?\s*[A-Za-z0-9\-–/]+\s*,\s*stall\s*(?:no\.?|#)?\s*[:\-]?\s*[A-Za-z0-9\-–/]+\b',
    caseSensitive: false,
  );
  static final taxPattern = RegExp(
    r'\b(?:gstin|gst|pan|cin|vat|tin)\s*[:#\-]?\s*([0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}|[A-Z]{5}[0-9]{4}[A-Z]{1}|[0-9A-Z]{10,21})\b',
    caseSensitive: false,
  );
  static final productTagline = RegExp(
    r'\b(?:manufacturers?|dealers?|exporters?|importers?|suppliers?|stockists?|specialists?|distributors?|wholesalers?)\s+(?:of|in)\b|\b(?:all\s+kinds\s+of|we\s+deal\s+in|iso\s*\d+[:\-]?\d*|certified\s+company|our\s+services|services\s+offered|single\s+window|approval|approvals|certification|clarification|coaching\s+classes|coaching|portal)\b',
    caseSensitive: false,
  );

  static bool isGenericTagline(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return true;
    if (productTagline.hasMatch(trimmed)) return true;
    return RegExp(
          r'^(?:elevators?\s*[&%]\s*escalators?|all\s+interior.*|interior\s*[&-]\s*exterior.*|engineers?\s*[&-]\s*contractors?|civil\s+engineers?|builders?\s*[&-]\s*contractors?|construction.*|entertainment|events?|car accessories|trading\s*company|travels?\s*&?\s*tours?|our\s+services.*|.*approval.*|.*certification.*|.*clarification.*|coaching.*|single\s+window.*)$',
          caseSensitive: false,
        ).hasMatch(trimmed) ||
        RegExp(
          r'^[A-Za-z\s]+(?:\s*[-–|/]\s*[A-Za-z\s]+){2,}$',
          caseSensitive: false,
        ).hasMatch(trimmed);
  }

  static BusinessCardData parse(String text) {
    final rawLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((e) => e.length > 1)
        .toList();

    // 1. Detect Trade Show Stall / Booth, Tax information & Order Notes
    String stallInfo = '';
    String orderNote = '';
    final notePattern = RegExp(
      r'^\s*\(?(?:all\s+)?(?:party|bulk|catering|corporate)?\s*orders?\s+(?:undertaken|accepted)\)?|\b(?:we\s+undertake|free\s+home\s+delivery|bulk\s+orders?\s+accepted)\b',
      caseSensitive: false,
    );
    final dividerPattern = RegExp(r'^[_\-=~*·•oO\s]{3,}$');
    final lines = <String>[];
    for (final line in rawLines) {
      if (dividerPattern.hasMatch(line)) continue;
      final stallMatch = stallPattern.firstMatch(line);
      if (stallMatch != null) {
        stallInfo = line;
        continue;
      }
      if (taxPattern.hasMatch(line) && !line.toLowerCase().contains('email') && !line.contains('@')) {
        continue;
      }
      if (notePattern.hasMatch(line)) {
        orderNote = line;
        continue;
      }
      lines.add(line);
    }

    String match(RegExp exp) => lines.where(exp.hasMatch).firstOrNull ?? '';
    bool contact(String line) =>
        email.hasMatch(line) ||
        isPhoneLine(line) ||
        web.hasMatch(line) ||
        stallPattern.hasMatch(line);

    List<String> unique(Iterable<String> values) => values
        .map((e) => e.replaceAll(RegExp(r'^[,|;\s]+|[,|;\s]+$'), '').trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final contactText = lines
        .map((line) {
          if (line.contains('@')) {
            final at = line.indexOf('@');
            final before = line.substring(0, at).trim().split(RegExp(r'\s+'));
            var local = before.last;
            if (before.length > 1 &&
                RegExp(r'[A-Za-z].*\d$').hasMatch(before[before.length - 2]) &&
                RegExp(r'^\d+$').hasMatch(local)) {
              local = '${before[before.length - 2]}$local';
            }
            local = local.replaceFirst(RegExp(r'^\d{5,}(?=[A-Za-z])'), '');
            final domain = line
                .substring(at + 1)
                .replaceAll(RegExp(r'\s+'), '');
            return '$local@$domain';
          }
          if (RegExp(
            r'\b(?:www\.|https?://)',
            caseSensitive: false,
          ).hasMatch(line)) {
            final start = RegExp(
              r'(?:www\.|https?://)',
              caseSensitive: false,
            ).firstMatch(line)!.start;
            return line.substring(start).replaceAll(RegExp(r'\s+'), '');
          }
          return line;
        })
        .join('\n');

    final emails = unique(
      email.allMatches(contactText).map((m) => m.group(0)!),
    );

    final textWithoutEmails = contactText.replaceAll(email, ' ');
    final websites = unique(
      web
          .allMatches(textWithoutEmails)
          .map((m) => m.group(0)!)
          .where(
            (w) =>
                RegExp(r'[A-Za-z]').hasMatch(w) &&
                RegExp(r'\.[A-Za-z]{2,}').hasMatch(w) &&
                !RegExp(
                  r'^(?:gmail|yahoo|outlook|hotmail)\.com$',
                  caseSensitive: false,
                ).hasMatch(w),
          ),
    );

    // 3. Cognitive Cross-Referencing: Match email username to Person & domain to Company
    const publicMail = {'gmail', 'yahoo', 'outlook', 'hotmail', 'zoho', 'rediffmail', 'icloud', 'proton'};
    String domainSlug = '';
    for (final em in emails) {
      final host = em.split('@').last.toLowerCase();
      final brand = host.split('.').first;
      if (!publicMail.contains(brand) && brand.length >= 3) {
        domainSlug = brand;
        break;
      }
    }
    if (domainSlug.isEmpty) {
      for (final wb in websites) {
        final host = wb.replaceFirst(RegExp(r'^(?:https?://)?(?:www\.)?', caseSensitive: false), '').toLowerCase();
        final brand = host.split('.').first;
        if (!publicMail.contains(brand) && brand.length >= 3) {
          domainSlug = brand;
          break;
        }
      }
    }

    final emailUserTokens = <String>[];
    if (emails.isNotEmpty) {
      final userPart = emails.first.split('@').first.toLowerCase();
      emailUserTokens.addAll(
        userPart
            .split(RegExp(r'[^a-z0-9]'))
            .where((t) => t.isNotEmpty && !RegExp(r'^\d+$').hasMatch(t) && !{'info', 'sales', 'contact', 'admin', 'support', 'mail'}.contains(t)),
      );
    }

    String? cognitiveCompany;
    if (domainSlug.isNotEmpty) {
      // 1. Single line match: exact match, or cleanLine starts with domainSlug, or covers >= 70% of domain
      for (final line in lines) {
        if (contact(line) || addresses.hasMatch(line) || titles.hasMatch(line) || productTagline.hasMatch(line)) continue;
        final cleanLine = line.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        if (cleanLine == domainSlug ||
            (cleanLine.startsWith(domainSlug) && domainSlug.length >= 6) ||
            (domainSlug.startsWith(cleanLine) && cleanLine.length >= domainSlug.length * 0.70)) {
          cognitiveCompany = line;
          break;
        }
        final tokens = line.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
        if (tokens.length >= 2 && tokens.every((t) => domainSlug.contains(t)) && cleanLine.length >= domainSlug.length * 0.70) {
          cognitiveCompany = line;
          break;
        }
        if (tokens.length >= 2) {
          final firstPlusInitials = tokens.first + tokens.skip(1).map((w) => w[0]).join();
          if (firstPlusInitials == domainSlug) {
            cognitiveCompany = line;
            break;
          }
          final allInitials = tokens.map((w) => w[0]).join();
          if (allInitials == domainSlug) {
            cognitiveCompany = line;
            break;
          }
        }
      }

      // 2. Multi-line heading match: when two adjacent heading lines together form the domain
      if (cognitiveCompany == null) {
        for (var i = 0; i < lines.length - 1; i++) {
          final l1 = lines[i];
          final l2 = lines[i + 1];
          if (contact(l1) ||
              contact(l2) ||
              addresses.hasMatch(l1) ||
              addresses.hasMatch(l2) ||
              productTagline.hasMatch(l1) ||
              productTagline.hasMatch(l2) ||
              titles.hasMatch(l2) ||
              _isLikelyPersonName(l2) ||
              l2.toLowerCase().startsWith('proprietor')) {
            continue;
          }
          final combinedClean = (l1 + l2).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
          final domainClean = domainSlug.replaceAll('and', '');
          final tokens = '$l1 $l2'.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length >= 2);
          if ((combinedClean == domainSlug ||
                  combinedClean == domainClean ||
                  tokens.every((t) => domainSlug.contains(t))) &&
              combinedClean.length >= domainClean.length * 0.75) {
            cognitiveCompany = '$l1 $l2';
            break;
          }
        }
      }
    }

    String? cognitivePerson;
    if (emailUserTokens.isNotEmpty) {
      for (final line in lines) {
        if (contact(line) || addresses.hasMatch(line) || titles.hasMatch(line) || line == cognitiveCompany) continue;
        final lineTokens = line.toLowerCase().split(RegExp(r'[^a-z]')).where((t) => t.isNotEmpty).toList();
        if (lineTokens.isEmpty) continue;
        final matchCount = lineTokens.where((t) => emailUserTokens.contains(t)).length;
        if (matchCount > 0 && (matchCount >= emailUserTokens.length || matchCount >= 2 || (lineTokens.length == 1 && lineTokens.first.length >= 4))) {
          cognitivePerson = line;
          break;
        }
      }
    }

    // 4. Check for inline name + title:
    // Format A: "Title: Name" (e.g. "Proprietor: R.AMINA", "Prop. R.AMINA", "Director: John Doe", "Contact: Alice")
    // Format B: "Name - Title", "Name (Title)", "Name, Title"
    String inlineName = '';
    String inlineTitle = '';
    for (final line in lines) {
      if (contact(line) || addresses.hasMatch(line) || line == cognitiveCompany) continue;

      // Prefix Format: "Title : Name"
      final prefixMatch = RegExp(
        r'^(?:(proprietor|prop\.?|owner|founder|co-founder|director|managing director|md|partner|managing partner|president|secretary|chairman|ceo|cto|cfo|coo|manager|head|consultant|architect|engineer|er\.?|dr\.?|adv\.?|advocate|contact person|contact|name))\s*[:\-–|]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (prefixMatch != null) {
        final rawTitle = prefixMatch.group(1)!.trim();
        final candName = prefixMatch.group(2)!.trim();
        if (_isLikelyPersonName(candName) || RegExp(r'^(?:[A-Za-z]\.\s*)+[A-Za-z]+$', caseSensitive: false).hasMatch(candName)) {
          inlineName = candName;
          final low = rawTitle.toLowerCase();
          inlineTitle = (low == 'prop' || low == 'prop.')
              ? 'Proprietor'
              : (low == 'name' || low == 'contact' || low == 'contact person' ? '' : rawTitle);
          break;
        }
      }

      // Suffix Format: "Name - Title"
      final dashMatch = RegExp(r"^([A-Za-z .\-'’]{2,40})\s*[\-–|]\s*(.+)$").firstMatch(line);
      if (dashMatch != null) {
        final candName = dashMatch.group(1)!.trim();
        final candTitle = dashMatch.group(2)!.trim();
        if (titles.hasMatch(candTitle) && (_isLikelyPersonName(candName) || RegExp(r'^(?:[A-Za-z]\.\s*)+[A-Za-z]+$', caseSensitive: false).hasMatch(candName))) {
          inlineName = candName;
          inlineTitle = candTitle;
          break;
        }
      }

      // Format: "Name (Title)"
      final parenMatch = RegExp(r"^([A-Za-z .\-'’]{2,40})\s*\(([^)]+)\)$").firstMatch(line);
      if (parenMatch != null) {
        final candName = parenMatch.group(1)!.trim();
        final candTitle = parenMatch.group(2)!.trim();
        if (titles.hasMatch(candTitle) && (_isLikelyPersonName(candName) || RegExp(r'^(?:[A-Za-z]\.\s*)+[A-Za-z]+$', caseSensitive: false).hasMatch(candName))) {
          inlineName = candName;
          inlineTitle = candTitle;
          break;
        }
      }

      // Format: "Name, Title"
      final commaMatch = RegExp(r"^([A-Za-z .\-'’]{2,40})\s*,\s*(.+)$").firstMatch(line);
      if (commaMatch != null) {
        final candName = commaMatch.group(1)!.trim();
        final candTitle = commaMatch.group(2)!.trim();
        if (titles.hasMatch(candTitle) && (_isLikelyPersonName(candName) || RegExp(r'^(?:[A-Za-z]\.\s*)+[A-Za-z]+$', caseSensitive: false).hasMatch(candName))) {
          inlineName = candName;
          inlineTitle = candTitle;
          break;
        }
      }
    }

    // 5. Extract person names
    final names = lines.where((line) {
      if (contact(line) ||
          companies.hasMatch(line) ||
          addresses.hasMatch(line) ||
          titles.hasMatch(line) ||
          productTagline.hasMatch(line) ||
          line == cognitiveCompany) {
        return false;
      }
      return _isLikelyPersonName(line);
    }).toList();

    var personName = cognitivePerson ?? (inlineName.isNotEmpty ? inlineName : (names.firstOrNull ?? ''));
    var jobTitle = inlineTitle.isNotEmpty ? inlineTitle : match(titles);

    // 6. Extract company name (supporting multi-line brand headings)
    String companyName = cognitiveCompany ?? '';
    if (companyName.isEmpty) {
      final compIdx = lines.indexWhere(
        (l) =>
            companies.hasMatch(l) &&
            !productTagline.hasMatch(l) &&
            !isGenericTagline(l) &&
            !contact(l) &&
            l != personName &&
            !titles.hasMatch(l) &&
            !l.toLowerCase().startsWith('proprietor'),
      );

      if (compIdx >= 0) {
        final compLine = lines[compIdx];
        final brandParts = <String>[];
        var startIdx = compIdx;
        while (startIdx > 0) {
          final prev = lines[startIdx - 1];
          if (contact(prev) ||
              addresses.hasMatch(prev) ||
              titles.hasMatch(prev) ||
              prev == personName ||
              isGenericTagline(prev) ||
              prev.length > 35) {
            break;
          }
          final words = prev.trim().split(RegExp(r'\s+'));
          if (words.isNotEmpty &&
              words.length <= 4 &&
              RegExp(r"^[A-Za-z0-9 .&'\-]+$").hasMatch(prev)) {
            brandParts.insert(0, prev);
            startIdx--;
          } else {
            break;
          }
        }
        brandParts.add(compLine);
        companyName = brandParts.join(' ');
      } else {
        final logoCompany = lines.where((line) {
          final letters = RegExp(r'[A-Za-z]').allMatches(line).length;
          final upper = RegExp(r'[A-Z]').allMatches(line).length;
          return !contact(line) &&
              !titles.hasMatch(line) &&
              !productTagline.hasMatch(line) &&
              !addresses.hasMatch(line) &&
              line != personName &&
              letters >= 3 &&
              line.length <= 40 &&
              (upper / letters >= .75 ||
                  (letters >= 5 &&
                      RegExp(r'^[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*$').hasMatch(line)));
        }).firstOrNull;
        companyName = logoCompany ?? '';
      }
    }

    if (companyName.isNotEmpty && !companyName.contains(' ') && emails.isNotEmpty) {
      final domainBrand = emails.first.split('@').last.split('.').first;
      final normalizedCompany = companyName
          .replaceAll(RegExp(r'[^A-Za-z]'), '')
          .toLowerCase();
      if (normalizedCompany.endsWith(domainBrand.toLowerCase()) &&
          normalizedCompany.length - domainBrand.length <= 2) {
        companyName = domainBrand.toUpperCase();
      }
    }

    // 7. Robust Phone Number Extraction
    final phones = _extractPhones(lines, rawText: text);

    // 8. Address Extraction
    final postalIndex = lines.indexWhere(
      (line) =>
          RegExp(
            r'\b\d{3}\s?\d{3}\b|\b\d{5}(?:-\d{4})?\b|\b(?:chennai|mumbai|delhi|kolkata|bangalore|hyderabad|pune)\s*[-–]?\s*\d{1,3}\b',
            caseSensitive: false,
          ).hasMatch(line) &&
          !email.hasMatch(line) &&
          !web.hasMatch(line),
    );

    final addressLines = <String>[];
    if (postalIndex >= 0) {
      for (var index = 0; index < lines.length; index++) {
        final cleaned = lines[index].replaceAll(email, '').trim();
        if (cleaned.isEmpty ||
            web.hasMatch(cleaned) ||
            titles.hasMatch(cleaned) ||
            companies.hasMatch(cleaned) ||
            productTagline.hasMatch(cleaned) ||
            taxPattern.hasMatch(cleaned) ||
            stallPattern.hasMatch(cleaned) ||
            isPhoneLine(cleaned)) {
          continue;
        }
        if (addresses.hasMatch(cleaned) ||
            RegExp(
              r'[,#]|\b(?:no\.?|block|floor)\b',
              caseSensitive: false,
            ).hasMatch(cleaned)) {
          addressLines.add(cleaned);
        }
      }
    } else {
      addressLines.addAll(
        lines
            .map((line) => line.replaceAll(email, '').trim())
            .where(
              (line) =>
                  addresses.hasMatch(line) &&
                  !productTagline.hasMatch(line) &&
                  !taxPattern.hasMatch(line) &&
                  !stallPattern.hasMatch(line) &&
                  !isPhoneLine(line) &&
                  !web.hasMatch(line),
            )
            .take(3),
      );
    }

    final used = <String>{
      if (personName.isNotEmpty) personName,
      if (jobTitle.isNotEmpty) jobTitle,
      companyName,
      ...addressLines,
    };

    final other = lines.where((line) {
      return !used.contains(line) &&
          !contact(line) &&
          !RegExp(r'^[|•·\-=]+$').hasMatch(line);
    }).toList();

    return BusinessCardData(
      name: personName,
      jobTitle: jobTitle,
      company: companyName,
      email: emails.firstOrNull ?? '',
      phone: phones.firstOrNull ?? '',
      website: websites.firstOrNull ?? '',
      address: addressLines
          .map(
            (line) => line
                .replaceFirst(RegExp(r'[,;]\s*$'), '')
                .replaceAllMapped(
                  RegExp(r'\b(\d{3})\s+(\d{3})\b'),
                  (match) => '${match[1]}${match[2]}',
                ),
          )
          .join(', '),
      stall: stallInfo,
      notes: orderNote,
      rawText: text,
      additionalEmails: emails.skip(1).toList(),
      additionalPhones: phones.skip(1).toList(),
      additionalWebsites: websites.skip(1).toList(),
      otherFields: other,
    );
  }

  static bool _isLikelyPersonName(String line) {
    final cleaned = line
        .replaceFirst(
          RegExp(r'^(?:Mr\.?|Mrs\.?|Ms\.?|Dr\.?|Er\.?|Prof\.?|CA)\s+', caseSensitive: false),
          '',
        )
        .trim();
    if (cleaned.isEmpty ||
        isPhoneLine(cleaned) ||
        stallPattern.hasMatch(cleaned) ||
        taxPattern.hasMatch(cleaned) ||
        RegExp(r'^[_\-=~*·•oO\s]{3,}$').hasMatch(cleaned)) {
      return false;
    }
    // Dotted initials (e.g. R.AMINA, G.Purushothaman, S. Mangayarkarasi)
    if (RegExp(r'^(?:[A-Za-z]\.\s*)+[A-Za-z]+$', caseSensitive: false).hasMatch(cleaned)) {
      return true;
    }
    final words = cleaned.split(RegExp(r'\s+'));
    return words.isNotEmpty &&
        words.length <= 4 &&
        cleaned.length <= 45 &&
        RegExp(r"^[A-Za-z .\-'’]+$").hasMatch(cleaned) &&
        !titles.hasMatch(cleaned) &&
        !companies.hasMatch(cleaned) &&
        !productTagline.hasMatch(cleaned) &&
        !isGenericTagline(cleaned);
  }

  static bool isPhoneLine(String line) {
    if (line.contains('@') || web.hasMatch(line)) return false;
    if (addresses.hasMatch(line) &&
        !RegExp(r'\b(?:phone|ph|mob|mobile|cell|tel|wa|whatsapp)\b', caseSensitive: false).hasMatch(line)) {
      return false;
    }
    final digits = line.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return false;
    if (digits.length == 6 && RegExp(r'^\s*\d{6}\s*$').hasMatch(line)) return false;
    if (digits.length == 8 && (digits.startsWith('19') || digits.startsWith('20'))) return false;

    if (RegExp(
      r'\b(?:phone|ph|mob|mobile|cell|tel|wa|whatsapp|contact)\b|\b[mw]\b|\+\d|\(\d{2,}\)|\d{4,}[\s\-]\d{4,}',
      caseSensitive: false,
    ).hasMatch(line)) {
      return true;
    }
    return RegExp(r'^\s*(?:\(?\+?\d{1,4}\)?[\s\-]?)?[6-9]\d{9}\s*$').hasMatch(line) ||
        RegExp(r'^\s*(?:\(?\+?\d{1,4}\)?[\s\-]?)?\d{3,5}[\s\-]\d{4,7}\s*$').hasMatch(line);
  }

  static List<String> _extractPhones(List<String> lines, {required String rawText}) {
    final results = <String>[];
    String? inheritedCountryCode;

    void addPhone(String raw, {bool isWhatsApp = false}) {
      var cleaned = raw
          .replaceAll(
            RegExp(r'^(?:ph|phone|mob|mobile|cell|tel|m|w|contact|wa|whatsapp)\s*[:.\-]?\s*', caseSensitive: false),
            '',
          )
          .replaceAllMapped(RegExp(r'^\(?\+(\d+)\)?\s*'), (m) => '+${m[1]} ')
          .replaceAll(RegExp(r'^[,|;/\s]+|[,|;/\s]+$'), '')
          .trim();
      final digits = cleaned.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 7 || digits.length > 15) return;
      if (digits.length == 6) return; // Postal codes
      if (digits.length == 8 && (digits.startsWith('19') || digits.startsWith('20'))) return; // Dates

      if (cleaned.startsWith('+')) {
        final m = RegExp(r'^\+\d{1,4}').firstMatch(cleaned);
        if (m != null) inheritedCountryCode = m.group(0);
      } else if (inheritedCountryCode != null && digits.length == 10 && !cleaned.startsWith('+')) {
        cleaned = '$inheritedCountryCode $cleaned';
      }

      if (isWhatsApp && !cleaned.toLowerCase().contains('whatsapp')) {
        cleaned = '$cleaned (WhatsApp)';
      }

      if (!results.contains(cleaned)) {
        results.add(cleaned);
      }
    }

    for (final line in lines) {
      if (line.contains('@') ||
          taxPattern.hasMatch(line) ||
          stallPattern.hasMatch(line) ||
          (!isPhoneLine(line) && addresses.hasMatch(line) && !line.toLowerCase().contains('mob'))) {
        continue;
      }
      final linePrefixWA = RegExp(r'^\s*(?:whatsapp|wa)[:\s-]', caseSensitive: false).hasMatch(line);
      if (line.contains('/') || line.contains(',') || line.contains('|')) {
        final segments = line.split(RegExp(r'[/,|]'));
        for (final seg in segments) {
          final segHasWA = linePrefixWA || RegExp(r'\b(?:whatsapp|wa)\b', caseSensitive: false).hasMatch(seg);
          final m = phone.firstMatch(seg);
          if (m != null) {
            addPhone(m.group(0)!, isWhatsApp: segHasWA);
          } else {
            final pureMobile = RegExp(r'\b[6-9]\d{9}\b').firstMatch(seg);
            if (pureMobile != null) {
              addPhone(pureMobile.group(0)!, isWhatsApp: segHasWA);
            }
          }
        }
      } else {
        final lineHasWA = RegExp(r'\b(?:whatsapp|wa)\b', caseSensitive: false).hasMatch(line);
        var found = false;
        for (final m in phone.allMatches(line)) {
          addPhone(m.group(0)!, isWhatsApp: lineHasWA);
          found = true;
        }
        if (!found) {
          final pureMobile = RegExp(r'\b[6-9]\d{9}\b').firstMatch(line);
          if (pureMobile != null) {
            addPhone(pureMobile.group(0)!, isWhatsApp: lineHasWA);
          }
        }
      }
    }

    if (results.isEmpty) {
      for (final m in phone.allMatches(rawText)) {
        addPhone(m.group(0)!);
      }
    }

    return results;
  }
}
