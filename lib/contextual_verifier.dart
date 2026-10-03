import 'card_parser.dart';

enum VerificationLevel {
  verified,
  inferred,
  unlikely,
  empty,
}

class FieldValidation {
  const FieldValidation({
    required this.level,
    required this.message,
  });

  final VerificationLevel level;
  final String message;

  bool get isVerified => level == VerificationLevel.verified;
  bool get isInferred => level == VerificationLevel.inferred;
  bool get isUnlikely => level == VerificationLevel.unlikely;
  bool get isEmpty => level == VerificationLevel.empty;
}

class ContextualCardVerifier {
  static const publicEmailDomains = {
    'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com',
    'icloud.com', 'zoho.com', 'rediffmail.com', 'mail.com',
    'proton.me', 'protonmail.com', 'ymail.com',
  };

  static FieldValidation verifyName(String name, {String email = ''}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const FieldValidation(
        level: VerificationLevel.empty,
        message: 'No name detected',
      );
    }
    if (RegExp(r'\d').hasMatch(trimmed) || trimmed.contains('@')) {
      return const FieldValidation(
        level: VerificationLevel.unlikely,
        message: 'Contains digits or symbols unlikely for a name',
      );
    }
    if (BusinessCardParser.companies.hasMatch(trimmed) ||
        BusinessCardParser.isGenericTagline(trimmed)) {
      return const FieldValidation(
        level: VerificationLevel.unlikely,
        message: 'Matches company or business tagline',
      );
    }

    // Check correlation with email identity
    if (email.contains('@')) {
      final userPart = email.split('@').first.toLowerCase();
      final tokens = userPart.split(RegExp(r'[^a-z0-9]')).where((t) => t.length >= 2);
      final cleanName = trimmed.toLowerCase();
      if (tokens.isNotEmpty && tokens.any((t) => cleanName.contains(t))) {
        return const FieldValidation(
          level: VerificationLevel.verified,
          message: 'Confirmed by email identity',
        );
      }
    }

    final words = trimmed.split(RegExp(r'\s+'));
    if (words.isNotEmpty && words.length <= 4) {
      final hasInitials = RegExp(r'\b[A-Za-z]\.').hasMatch(trimmed);
      if (hasInitials) {
        return const FieldValidation(
          level: VerificationLevel.verified,
          message: 'Valid name with initials',
        );
      }
      return const FieldValidation(
        level: VerificationLevel.verified,
        message: 'Standard person name',
      );
    }
    return const FieldValidation(
      level: VerificationLevel.inferred,
      message: 'Name has unusual word count, please verify',
    );
  }

  static FieldValidation verifyCompany(
    String company, {
    String email = '',
    String website = '',
  }) {
    final trimmed = company.trim();
    if (trimmed.isEmpty) {
      return const FieldValidation(
        level: VerificationLevel.empty,
        message: 'No company detected',
      );
    }
    if (BusinessCardParser.isGenericTagline(trimmed)) {
      return const FieldValidation(
        level: VerificationLevel.unlikely,
        message: 'Looks like a generic service tagline',
      );
    }

    // Check correlation with email / web domain
    final normalizedCompany = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
    String? domainBrand;
    if (email.contains('@')) {
      final domain = email.split('@').last.toLowerCase();
      if (!publicEmailDomains.contains(domain)) {
        domainBrand = domain.split('.').first;
      }
    }
    if (domainBrand == null && website.isNotEmpty) {
      final cleanedWeb = website.replaceFirst(RegExp(r'^(?:https?://)?(?:www\.)?'), '').toLowerCase();
      final brandPart = cleanedWeb.split('.').first;
      if (!publicEmailDomains.contains('$brandPart.com')) {
        domainBrand = brandPart;
      }
    }

    if (domainBrand != null && domainBrand.length >= 3) {
      if (normalizedCompany.contains(domainBrand) || domainBrand.contains(normalizedCompany)) {
        return FieldValidation(
          level: VerificationLevel.verified,
          message: 'Confirmed by domain "$domainBrand"',
        );
      }
    }

    if (BusinessCardParser.companies.hasMatch(trimmed)) {
      return const FieldValidation(
        level: VerificationLevel.verified,
        message: 'Recognized business or trade type',
      );
    }

    return const FieldValidation(
      level: VerificationLevel.inferred,
      message: 'Inferred from card heading',
    );
  }

  static FieldValidation verifyPhone(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) {
      return const FieldValidation(
        level: VerificationLevel.empty,
        message: 'No phone number',
      );
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 6) {
      return const FieldValidation(
        level: VerificationLevel.unlikely,
        message: '6-digit number looks like a postal code',
      );
    }
    if (digits.length < 7 || digits.length > 15) {
      return const FieldValidation(
        level: VerificationLevel.unlikely,
        message: 'Unusual phone digit length',
      );
    }
    if (digits.length == 10 && RegExp(r'^[6-9]').hasMatch(digits)) {
      return const FieldValidation(
        level: VerificationLevel.verified,
        message: 'Valid 10-digit mobile number',
      );
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      return const FieldValidation(
        level: VerificationLevel.verified,
        message: 'Valid +91 mobile number',
      );
    }
    return const FieldValidation(
      level: VerificationLevel.verified,
      message: 'Valid phone format',
    );
  }

  static FieldValidation verifyEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      return const FieldValidation(
        level: VerificationLevel.empty,
        message: 'No email on card',
      );
    }
    if (!BusinessCardParser.email.hasMatch(trimmed)) {
      return const FieldValidation(
        level: VerificationLevel.unlikely,
        message: 'Invalid email structure',
      );
    }
    final domain = trimmed.split('@').last.toLowerCase();
    if (publicEmailDomains.contains(domain)) {
      return const FieldValidation(
        level: VerificationLevel.verified,
        message: 'Personal / public webmail',
      );
    }
    return const FieldValidation(
      level: VerificationLevel.verified,
      message: 'Corporate business email',
    );
  }

  static FieldValidation verifyWebsite(String website) {
    final trimmed = website.trim();
    if (trimmed.isEmpty) {
      return const FieldValidation(
        level: VerificationLevel.empty,
        message: 'No website on card',
      );
    }
    if (BusinessCardParser.web.hasMatch(trimmed)) {
      return const FieldValidation(
        level: VerificationLevel.verified,
        message: 'Valid web address',
      );
    }
    return const FieldValidation(
      level: VerificationLevel.inferred,
      message: 'Check web URL formatting',
    );
  }

  static FieldValidation verifyAddress(String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      return const FieldValidation(
        level: VerificationLevel.empty,
        message: 'No address on card',
      );
    }
    final hasPostal = RegExp(r'\b\d{3}\s?\d{3}\b|\b\d{5}\b|\b(?:chennai|mumbai|delhi|kolkata|bangalore|hyderabad|pune)\s*[-–]?\s*\d{1,3}\b', caseSensitive: false).hasMatch(trimmed);
    final hasStreet = BusinessCardParser.addresses.hasMatch(trimmed);
    if (hasPostal && hasStreet) {
      return const FieldValidation(
        level: VerificationLevel.verified,
        message: 'Complete address with postal code/zone',
      );
    }
    if (hasStreet) {
      return const FieldValidation(
        level: VerificationLevel.verified,
        message: 'Street & locality address',
      );
    }
    return const FieldValidation(
      level: VerificationLevel.inferred,
      message: 'Partial address detected',
    );
  }

  static FieldValidation verifyStall(String stall) {
    final trimmed = stall.trim();
    if (trimmed.isEmpty) {
      return const FieldValidation(
        level: VerificationLevel.empty,
        message: 'Optional expo stall',
      );
    }
    if (BusinessCardParser.stallPattern.hasMatch(trimmed)) {
      return const FieldValidation(
        level: VerificationLevel.verified,
        message: 'Expo stall / booth recognized',
      );
    }
    return const FieldValidation(
      level: VerificationLevel.inferred,
      message: 'Stall identifier',
    );
  }
}
