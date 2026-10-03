import 'package:card_lens/card_parser.dart';
import 'package:card_lens/contextual_verifier.dart';
import 'package:card_lens/field_classifier.dart';
import 'package:card_lens/ocr_service.dart';
import 'package:card_lens/saved_cards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts the main business card fields', () {
    const source = '''
Jane A. Doe
Product Director
Bright Future Technologies Pvt. Ltd.
jane.doe@brightfuture.com
+91 98765 43210
www.brightfuture.com
12 Park Road, Bengaluru 560001
''';
    final card = BusinessCardParser.parse(source);
    expect(card.name, 'Jane A. Doe');
    expect(card.jobTitle, 'Product Director');
    expect(card.company, contains('Bright Future'));
    expect(card.email, 'jane.doe@brightfuture.com');
    expect(card.phone, '+91 98765 43210');
    expect(card.website, 'www.brightfuture.com');
    expect(card.address, contains('560001'));
  });

  test('keeps company, multiline address, and every email and website', () {
    const source = '''
Samaira Kapoor
Graphic Designer
EYESHIV
+91-99103 69326 (WhatsApp)
www.eyeshiv.com | www.shop.eyeshiv.com
info@eyeshiv.com, eyeshiv@gmail.com
38 A, Vasant Kunj Phase 1,
New Delhi-110070
''';
    final card = BusinessCardParser.parse(source);
    expect(card.name, 'Samaira Kapoor');
    expect(card.company, 'EYESHIV');
    expect(card.email, 'info@eyeshiv.com');
    expect(card.additionalEmails, contains('eyeshiv@gmail.com'));
    expect(card.website, 'www.eyeshiv.com');
    expect(card.additionalWebsites, contains('www.shop.eyeshiv.com'));
    expect(card.additionalWebsites, isNot(contains('eyeshiv.com')));
    expect(card.website, isNot('+91-99103 69326'));
    expect(card.address, contains('38 A, Vasant Kunj Phase 1'));
    expect(card.address, contains('New Delhi-110070'));
  });

  test('does not treat a phone-only line as an address', () {
    const source = '''
Landess Builder
Guru Kathiresan
Chief Product Officer
info@landessware.com
+91 73056 72310
www.landessware.com
''';
    final card = BusinessCardParser.parse(source);
    expect(card.phone, '+91 73056 72310');
    expect(card.address, isEmpty);
  });

  test(
    'uses the line above the title as name and heading as company',
    () async {
      const source = '''
Landess Builder
Construction ERP Made Easy
Guru Kathiresan
Chief Product Officer
info@landessware.com
+91 73056 72310
www.landessware.com
''';
      const layout = [
        OcrLine(text: 'Landess Builder', top: 10, left: 10, height: 24),
        OcrLine(
          text: 'Construction ERP Made Easy',
          top: 38,
          left: 10,
          height: 11,
        ),
        OcrLine(text: 'Guru Kathiresan', top: 75, left: 10, height: 19),
        OcrLine(text: 'Chief Product Officer', top: 98, left: 10, height: 13),
        OcrLine(text: 'info@landessware.com', top: 140, left: 10, height: 12),
        OcrLine(text: '+91 73056 72310', top: 160, left: 10, height: 12),
        OcrLine(text: 'www.landessware.com', top: 180, left: 10, height: 12),
      ];
      final card = await SmartBusinessCardParser.parse(source, layout: layout);
      expect(card.name, 'Guru Kathiresan');
      expect(card.company, 'Landess Builder');
      expect(card.address, isEmpty);
    },
  );

  test('resolves a director name separately from a tech company', () async {
    const source = '''
DEEPAM INFO TECH
M. Siva Kumar
Managing Director
+91 72000 44770
deepaminfotechpccare@gmail.com
www.deepaminfotech.com
''';
    const layout = [
      OcrLine(text: 'DEEPAM INFO TECH', top: 10, left: 10, height: 23),
      OcrLine(text: 'M. Siva Kumar', top: 48, left: 250, height: 18),
      OcrLine(text: 'Managing Director', top: 69, left: 250, height: 11),
      OcrLine(text: '+91 72000 44770', top: 100, left: 250, height: 11),
      OcrLine(
        text: 'deepaminfotechpccare@gmail.com',
        top: 120,
        left: 250,
        height: 10,
      ),
      OcrLine(text: 'www.deepaminfotech.com', top: 140, left: 250, height: 10),
    ];
    final card = await SmartBusinessCardParser.parse(source, layout: layout);
    expect(card.name, 'M. Siva Kumar');
    expect(card.company, 'DEEPAM INFO TECH');
  });

  test('recognizes construction branding without stealing the name', () async {
    const source = '''
Er. A. Balamurugan
Sree Vishnu Construction
Engineers & Contractors
+91 98422 35913
''';
    const layout = [
      OcrLine(text: 'Er. A. Balamurugan', top: 12, left: 10, height: 15),
      OcrLine(text: 'Sree Vishnu Construction', top: 55, left: 10, height: 25),
      OcrLine(text: 'Engineers & Contractors', top: 82, left: 10, height: 12),
      OcrLine(text: '+91 98422 35913', top: 110, left: 10, height: 11),
    ];
    final card = await SmartBusinessCardParser.parse(source, layout: layout);
    expect(card.name, 'Er. A. Balamurugan');
    expect(card.company, 'Sree Vishnu Construction');
  });

  test('keeps genuinely absent optional fields empty', () async {
    const source = '''
info@example.com
+91 98765 43210
www.example.com
''';
    const layout = [
      OcrLine(text: 'info@example.com', top: 10, left: 10, height: 12),
      OcrLine(text: '+91 98765 43210', top: 30, left: 10, height: 12),
      OcrLine(text: 'www.example.com', top: 50, left: 10, height: 12),
    ];
    final card = await SmartBusinessCardParser.parse(source, layout: layout);
    expect(card.name, isEmpty);
    expect(card.jobTitle, isEmpty);
    expect(card.company, isEmpty);
    expect(card.address, isEmpty);
  });

  test('does not mistake dotted names for websites', () async {
    const source = '''
MAAXSON LIFTS
ELEVATORS % ESCALATORS
DARENS.R
9884016999 /9514418555
www.maaxsonlifts.com
maaxsonlifts@gmail.com
CHENNAI BANGALORE SALEM COIMBATORE THIRUNELVELI
''';
    const layout = [
      OcrLine(text: 'MAAXSON LIFTS', top: 10, left: 10, height: 25),
      OcrLine(text: 'ELEVATORS % ESCALATORS', top: 38, left: 10, height: 12),
      OcrLine(text: 'DARENS.R', top: 68, left: 10, height: 18),
      OcrLine(text: '9884016999 /9514418555', top: 90, left: 10, height: 12),
      OcrLine(text: 'www.maaxsonlifts.com', top: 110, left: 10, height: 12),
    ];
    final card = await SmartBusinessCardParser.parse(source, layout: layout);
    expect(card.name, 'DARENS.R');
    expect(card.company, 'MAAXSON LIFTS');
    expect(card.website, 'www.maaxsonlifts.com');
  });

  test('uses contact domain when the company logo is missed by OCR', () async {
    const source = '''
M. Sheik Mohamed Alsafa
Managing Director
+91 93445 66488
sheik@greenglobalconstruction.com
122, 4th Cross Street, Anna Nagar,
Chennai - 600 040.
Construction- Interior Designing - Consultation
''';
    const layout = [
      OcrLine(text: 'M. Sheik Mohamed Alsafa', top: 10, left: 10, height: 18),
      OcrLine(text: 'Managing Director', top: 32, left: 10, height: 12),
      OcrLine(
        text: 'sheik@greenglobalconstruction.com',
        top: 70,
        left: 10,
        height: 10,
      ),
      OcrLine(
        text: 'Construction- Interior Designing - Consultation',
        top: 130,
        left: 10,
        height: 11,
      ),
    ];
    final card = await SmartBusinessCardParser.parse(source, layout: layout);
    expect(card.name, 'M. Sheik Mohamed Alsafa');
    expect(card.company, 'GREEN GLOBAL CONSTRUCTION');
    expect(card.address, contains('600040'));
  });

  test('joins spaced postcode and keeps multiline address', () {
    const source = '''
M. Siva Kumar
Managing Director
DEEPAM INFO TECH
P-250/1, Pasumpon Street,
MMDA Colony, Arumbakkam
Chennai 600 106.
''';
    final card = BusinessCardParser.parse(source);
    expect(card.address, contains('P-250/1'));
    expect(card.address, contains('600106'));
  });

  test('separates a phone number joined to an email by OCR', () {
    final card = BusinessCardParser.parse(
      '+91 94449 06225chennaieps@gmail.com',
    );
    expect(card.email, 'chennaieps@gmail.com');
    expect(card.phone, '+91 94449 06225');
  });

  test('prefers the card brand over an unrelated website above it', () async {
    const source = '''
Website:www.thaaiinteriors.com
SARAVANANG.K
Founder & thinker
ZinniAS
entertainment
www.zinnias.in
saravanan@zinnias.in
''';
    const layout = [
      OcrLine(
        text: 'Website:www.thaaiinteriors.com',
        top: 0,
        left: 0,
        height: 8,
      ),
      OcrLine(text: 'SARAVANANG.K', top: 20, left: 0, height: 18),
      OcrLine(text: 'Founder & thinker', top: 41, left: 0, height: 11),
      OcrLine(text: 'ZinniAS', top: 70, left: 0, height: 24),
      OcrLine(text: 'entertainment', top: 96, left: 0, height: 10),
    ];
    final card = await SmartBusinessCardParser.parse(source, layout: layout);
    expect(card.name, 'SARAVANANG.K');
    expect(card.company.toLowerCase(), 'zinnias');
  });

  test('extracts expo trade-show stall, filters GSTIN, and captures contact', () async {
    const source = '''
VERTEX PACKAGING
Vikram Malhotra
General Manager
Hall 3, Stall A-12
GSTIN: 27AABCV1234F1Z9
sales@vertexpack.com
+91 98201 11223 / 98201 11224 (WhatsApp)
www.vertexpack.com
Plot 45, GIDC Industrial Estate, Vapi, Gujarat 396195
''';
    final card = BusinessCardParser.parse(source);
    expect(card.company, 'VERTEX PACKAGING');
    expect(card.name, 'Vikram Malhotra');
    expect(card.jobTitle, 'General Manager');
    expect(card.stall, contains('Stall A-12'));
    expect(card.email, 'sales@vertexpack.com');
    expect(card.phone, '+91 98201 11223');
    expect(card.additionalPhones, contains('+91 98201 11224 (WhatsApp)'));
    expect(card.phone, isNot(contains('27AABCV1234F1Z9')));
    expect(card.address, contains('GIDC Industrial Estate'));
    expect(card.address, isNot(contains('27AABCV1234F1Z9')));
  });

  test('extracts inline name and designation correctly', () {
    const source = '''
ZENITH AUTOMATION
Amit Patel - Managing Director
amit@zenithauto.in
+91 98980 12345
www.zenithauto.in
''';
    final card = BusinessCardParser.parse(source);
    expect(card.name, 'Amit Patel');
    expect(card.jobTitle, 'Managing Director');
    expect(card.company, 'ZENITH AUTOMATION');
    expect(card.email, 'amit@zenithauto.in');
  });

  test('does not mistake product lists or manufacturing taglines for addresses or companies', () async {
    const source = '''
Ramesh Sharma
Proprietor
SHREE SHYAM ENTERPRISES
Manufacturers of: Corrugated Boxes, PP Strapping, Stretch Films
shreeshyam@gmail.com
+91 98100 54321
D-12, Sector 59, Noida 201301
''';
    final card = BusinessCardParser.parse(source);
    expect(card.name, 'Ramesh Sharma');
    expect(card.jobTitle, 'Proprietor');
    expect(card.company, 'SHREE SHYAM ENTERPRISES');
    expect(card.address, contains('Sector 59'));
    expect(card.address, isNot(contains('Manufacturers of')));
  });

  test('generates compliant vCard string with all expo details', () {
    final card = SavedCard(
      id: '12345',
      createdAt: DateTime(2026, 1, 1),
      imagePath: '/tmp/card.jpg',
      fields: const {
        'Full name': 'Vikram Malhotra',
        'Job title': 'General Manager',
        'Company': 'VERTEX PACKAGING',
        'Email': 'sales@vertexpack.com',
        'Phone': '+91 98201 11223',
        'Phone 2': '+91 98201 11224 (WhatsApp)',
        'Website': 'www.vertexpack.com',
        'Address': 'Plot 45, GIDC, Vapi 396195',
        'Stall / Booth': 'Hall 3, Stall A-12',
        'Notes': 'Met regarding bulk export quote',
      },
    );
    final vcf = card.toVCard();
    expect(vcf, contains('BEGIN:VCARD'));
    expect(vcf, contains('FN:Vikram Malhotra'));
    expect(vcf, contains('ORG:VERTEX PACKAGING'));
    expect(vcf, contains('TITLE:General Manager'));
    expect(vcf, contains('TEL;TYPE=CELL:+91 98201 11223'));
    expect(vcf, contains('TEL;TYPE=CELL:+91 98201 11224 (WhatsApp)'));
    expect(vcf, contains('EMAIL;TYPE=INTERNET:sales@vertexpack.com'));
    expect(vcf, contains('URL:www.vertexpack.com'));
    expect(vcf, contains('ADR;TYPE=WORK:;;Plot 45, GIDC, Vapi 396195;;;;'));
    expect(vcf, contains('NOTE:Stall/Booth: Hall 3, Stall A-12\\nMet regarding bulk export quote'));
    expect(vcf, contains('END:VCARD'));
  });

  test('sorts lines adaptively based on line height tolerance', () {
    const lines = [
      OcrLine(text: 'Line A', top: 100.0, left: 10.0, height: 40.0),
      OcrLine(text: 'Line B', top: 112.0, left: 200.0, height: 40.0), // Baseline shifted by 12px but same row
      OcrLine(text: 'Line C', top: 160.0, left: 10.0, height: 40.0),
    ];
    final sorted = OcrLine.sortAdaptively(lines);
    expect(sorted[0].text, 'Line A');
    expect(sorted[1].text, 'Line B');
    expect(sorted[2].text, 'Line C');
  });

  test('extracts traditional shop card with multi-line business name, initials, and city postal zone', () async {
    const source = '''
S. Mangayarkarasi
90800 29434
98412 32756
Muthukrishnan
Chettinad
Palagaram
(All Party Orders Undertaken)
45/26 Nerkundram Pathai, Valliammal Street Jayam Flats,
Vadapalani, Chennai 26.
''';
    const layout = [
      OcrLine(text: 'S. Mangayarkarasi', top: 10, left: 10, height: 18),
      OcrLine(text: '90800 29434', top: 10, left: 200, height: 14),
      OcrLine(text: '98412 32756', top: 28, left: 200, height: 14),
      OcrLine(text: 'Muthukrishnan', top: 60, left: 120, height: 26),
      OcrLine(text: 'Chettinad', top: 90, left: 130, height: 26),
      OcrLine(text: 'Palagaram', top: 120, left: 130, height: 26),
      OcrLine(text: '(All Party Orders Undertaken)', top: 155, left: 100, height: 14),
      OcrLine(
        text: '45/26 Nerkundram Pathai, Valliammal Street Jayam Flats,',
        top: 180,
        left: 20,
        height: 12,
      ),
      OcrLine(text: 'Vadapalani, Chennai 26.', top: 195, left: 20, height: 12),
    ];
    final card = await SmartBusinessCardParser.parse(source, layout: layout);
    expect(card.name, 'S. Mangayarkarasi');
    expect(card.company, 'Muthukrishnan Chettinad Palagaram');
    expect(card.phone, '90800 29434');
    expect(card.additionalPhones, contains('98412 32756'));
    expect(card.notes, contains('Orders Undertaken'));
    expect(card.address, contains('45/26 Nerkundram Pathai'));
    expect(card.address, contains('Chennai 26'));
  });

  test('verifies contextual card knowledge rules', () {
    final nameValid = ContextualCardVerifier.verifyName('S. Mangayarkarasi');
    expect(nameValid.isVerified, isTrue);

    final phoneValid = ContextualCardVerifier.verifyPhone('90800 29434');
    expect(phoneValid.isVerified, isTrue);

    final companyValid = ContextualCardVerifier.verifyCompany('Muthukrishnan Chettinad Palagaram');
    expect(companyValid.isVerified, isTrue);

    final addressValid = ContextualCardVerifier.verifyAddress(
      '45/26 Nerkundram Pathai, Valliammal Street Jayam Flats, Vadapalani, Chennai 26.',
    );
    expect(addressValid.isVerified, isTrue);

    final emptyEmail = ContextualCardVerifier.verifyEmail('');
    expect(emptyEmail.isEmpty, isTrue);
  });

  test('extracts GRP SPEED LOAN card using cognitive email/domain cross-referencing', () async {
    const source = '''
GRP SPEED LOAN
G.Purushothaman
-----------------------------o
9841056291
8610021252
purushothaman.g@grpspeedloan.com
www.grpspeedloan.com
No.9, 60th Street, 10 Avenue,
Ashok Nagar, Chennai 600083.
''';
    const layout = [
      OcrLine(text: 'GRP SPEED LOAN', top: 20, left: 10, height: 22),
      OcrLine(text: 'G.Purushothaman', top: 50, left: 10, height: 18),
      OcrLine(text: '-----------------------------o', top: 75, left: 10, height: 6),
      OcrLine(text: '9841056291', top: 95, left: 30, height: 14),
      OcrLine(text: '8610021252', top: 120, left: 30, height: 14),
      OcrLine(text: 'purushothaman.g@grpspeedloan.com', top: 145, left: 30, height: 14),
      OcrLine(text: 'www.grpspeedloan.com', top: 170, left: 30, height: 14),
      OcrLine(text: 'No.9, 60th Street, 10 Avenue,', top: 195, left: 30, height: 12),
      OcrLine(text: 'Ashok Nagar, Chennai 600083.', top: 215, left: 30, height: 12),
    ];
    final card = await SmartBusinessCardParser.parse(source, layout: layout);
    expect(card.company, 'GRP SPEED LOAN');
    expect(card.name, 'G.Purushothaman');
    expect(card.phone, '9841056291');
    expect(card.additionalPhones, contains('8610021252'));
    expect(card.email, 'purushothaman.g@grpspeedloan.com');
    expect(card.website, 'www.grpspeedloan.com');
    expect(card.address, contains('No.9, 60th Street, 10 Avenue'));
    expect(card.address, contains('Chennai 600083'));
  });

  test('verifies cognitive email/name and domain/company contextual validation', () {
    final nameValid = ContextualCardVerifier.verifyName(
      'G.Purushothaman',
      email: 'purushothaman.g@grpspeedloan.com',
    );
    expect(nameValid.isVerified, isTrue);
    expect(nameValid.message, contains('email identity'));

    final companyValid = ContextualCardVerifier.verifyCompany(
      'GRP SPEED LOAN',
      email: 'purushothaman.g@grpspeedloan.com',
      website: 'www.grpspeedloan.com',
    );
    expect(companyValid.isVerified, isTrue);
    expect(companyValid.message, contains('Confirmed by domain'));
  });

  test('extracts SMART HOME card with Proprietor prefix and multi-line brand heading', () async {
    const source = '''
SMART HOME
PLANNERS & ENGINEERS
Our Services
SINGLE WINDOW PORTAL
Greater Chennai Corporation
CMDA Approval
DTCP Approval
Municipality Approval
Panchayat Approval
Layout Approval
Reclassification Approval
Complition Certification
Quries Clarification
Coaching Classes
Proprietor: R.AMINA
8248554031
smarthomeplannersandengineers@gmail.com
smarthomeplannersandengineers.com
No.40, Eswaran Nagar, Avadi Main Road,
Redhills, Chennai - 600 052.
''';
    final card = BusinessCardParser.parse(source);
    expect(card.company, 'SMART HOME PLANNERS & ENGINEERS');
    expect(card.name, 'R.AMINA');
    expect(card.jobTitle, 'Proprietor');
    expect(card.phone, '8248554031');
    expect(card.email, 'smarthomeplannersandengineers@gmail.com');
    expect(card.website, 'smarthomeplannersandengineers.com');
    expect(card.address, contains('No.40, Eswaran Nagar'));
    expect(card.address, contains('Chennai - 600052'));
    expect(card.name, isNot(contains('Classes')));
    expect(card.name, isNot(contains('Corporation')));
  });

  test('extracts vertical BEAVER CONSTRUCTION COMPANY card with parenthesized phone and domain initials', () async {
    const source = '''
BCC
BEAVER CONSTRUCTION COMPANY
YUVASHREE
Transaction Manager
(+91) 9884783091
yuvashree@beavercc.in
www.beavercc.in
No.6-A "BEAVER'S NARAYANI", Ground Floor, Postal Colony, 3rd Main Road, West Mambalam, Chennai - 600 033.
''';
    final card = BusinessCardParser.parse(source);
    expect(card.company, 'BEAVER CONSTRUCTION COMPANY');
    expect(card.name, 'YUVASHREE');
    expect(card.jobTitle, 'Transaction Manager');
    expect(card.phone, '+91 9884783091');
    expect(card.email, 'yuvashree@beavercc.in');
    expect(card.website, 'www.beavercc.in');
    expect(card.address, contains('No.6-A "BEAVER\'S NARAYANI"'));
    expect(card.address, contains('Chennai - 600033'));
  });

  test('merges front and back sides of double-sided card without duplicates', () {
    const front = BusinessCardData(
      name: 'YUVASHREE',
      jobTitle: 'Transaction Manager',
      company: 'BEAVER CONSTRUCTION COMPANY',
      phone: '+91 9884783091',
      email: 'yuvashree@beavercc.in',
      website: 'www.beavercc.in',
      address: 'West Mambalam, Chennai - 600033',
    );
    const back = BusinessCardData(
      phone: '+91 9884783091', // duplicate phone
      additionalPhones: ['044 2489 1234'],
      email: 'yuvashree@beavercc.in', // duplicate email
      additionalEmails: ['sales@beavercc.in'],
      website: 'www.beaverhomes.in',
      address: 'Branch: No. 12 OMR, Chennai - 600096',
      notes: 'Villa & Flat Promoters in Chennai',
      otherFields: ['Residential Projects', 'Commercial Complex'],
    );

    final merged = BusinessCardData.merge(front, back);
    expect(merged.name, 'YUVASHREE');
    expect(merged.jobTitle, 'Transaction Manager');
    expect(merged.company, 'BEAVER CONSTRUCTION COMPANY');
    expect(merged.phone, '+91 9884783091');
    expect(merged.additionalPhones, contains('044 2489 1234'));
    expect(merged.additionalPhones, isNot(contains('+91 9884783091'))); // no duplicate
    expect(merged.email, 'yuvashree@beavercc.in');
    expect(merged.additionalEmails, contains('sales@beavercc.in'));
    expect(merged.website, 'www.beavercc.in');
    expect(merged.additionalWebsites, contains('www.beaverhomes.in'));
    expect(merged.address, contains('West Mambalam'));
    expect(merged.address, contains('Branch: No. 12 OMR'));
    expect(merged.notes, contains('Villa & Flat Promoters in Chennai'));
    expect(merged.notes, contains('Residential Projects, Commercial Complex'));
    expect(merged.rawText, contains('--- FRONT ---'));
    expect(merged.rawText, contains('--- BACK ---'));
  });

  test('generates Excel-compatible CSV with clickable WhatsApp wa.me and Google Maps links', () {
    final card = SavedCard(
      id: '12345',
      createdAt: DateTime(2026, 9, 7, 14, 30),
      imagePath: '/path/to/card.jpg',
      fields: {
        'Full name': 'Yuvashree',
        'Job title': 'Transaction Manager',
        'Company': 'Beaver Construction Company',
        'Phone': '+91 9884783091',
        'Email': 'yuvashree@beavercc.in',
        'Website': 'www.beavercc.in',
        'Address': 'West Mambalam, Chennai',
        'Stall / Booth': 'Hall 2, Stall B-14',
        'Notes': 'Needs brochure by tomorrow',
      },
    );

    final csv = SavedCardStore.generateCsv([card]);
    expect(csv.startsWith('\uFEFF'), isTrue); // Excel UTF-8 BOM
    expect(csv, contains('WhatsApp Direct Link'));
    expect(csv, contains('Google Maps Link'));
    expect(csv, contains('https://wa.me/919884783091'));
    expect(csv, contains('https://www.google.com/maps/search/?api=1&query='));
    expect(csv, contains('Hall 2, Stall B-14'));
    expect(csv, contains('Needs brochure by tomorrow'));
  });
}


