import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class MyProfile {
  const MyProfile({
    this.name = '',
    this.jobTitle = '',
    this.company = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.address = '',
    this.notes = '',
  });

  final String name;
  final String jobTitle;
  final String company;
  final String phone;
  final String email;
  final String website;
  final String address;
  final String notes;

  bool get isEmpty =>
      name.isEmpty &&
      company.isEmpty &&
      phone.isEmpty &&
      email.isEmpty;

  String toVCard() {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCARD');
    buffer.writeln('VERSION:3.0');
    final trimmedName = name.trim();
    buffer.writeln('FN:$trimmedName');
    final parts = trimmedName.split(' ');
    if (parts.length > 1) {
      buffer.writeln('N:${parts.last};${parts.sublist(0, parts.length - 1).join(' ')};;;');
    } else {
      buffer.writeln('N:$trimmedName;;;;');
    }
    if (company.trim().isNotEmpty) buffer.writeln('ORG:${company.trim()}');
    if (jobTitle.trim().isNotEmpty) buffer.writeln('TITLE:${jobTitle.trim()}');
    if (phone.trim().isNotEmpty) {
      final p = phone.trim();
      final isCell = p.startsWith('+') || p.toLowerCase().contains('whatsapp');
      buffer.writeln('TEL;TYPE=${isCell ? 'CELL' : 'WORK'}:$p');
    }
    if (email.trim().isNotEmpty) buffer.writeln('EMAIL;TYPE=INTERNET:${email.trim()}');
    if (website.trim().isNotEmpty) buffer.writeln('URL:${website.trim()}');
    if (address.trim().isNotEmpty) buffer.writeln('ADR;TYPE=WORK:;;${address.trim()};;;;');
    if (notes.trim().isNotEmpty) buffer.writeln('NOTE:${notes.trim()}');
    buffer.writeln('END:VCARD');
    return buffer.toString();
  }

  Map<String, String> toJson() => {
    'name': name,
    'jobTitle': jobTitle,
    'company': company,
    'phone': phone,
    'email': email,
    'website': website,
    'address': address,
    'notes': notes,
  };

  factory MyProfile.fromJson(Map<String, dynamic> json) => MyProfile(
    name: json['name'] as String? ?? '',
    jobTitle: json['jobTitle'] as String? ?? '',
    company: json['company'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    website: json['website'] as String? ?? '',
    address: json['address'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
  );
}

class MyProfileStore {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}my_profile.json');
  }

  static Future<MyProfile> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const MyProfile();
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return MyProfile.fromJson(data);
    } catch (_) {
      return const MyProfile();
    }
  }

  static Future<void> save(MyProfile profile) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }
}

class MyQrPage extends StatefulWidget {
  const MyQrPage({super.key});

  @override
  State<MyQrPage> createState() => _MyQrPageState();
}

class _MyQrPageState extends State<MyQrPage> {
  MyProfile _profile = const MyProfile();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final p = await MyProfileStore.load();
    if (mounted) {
      setState(() {
        _profile = p;
        _loading = false;
      });
    }
  }

  void _openEditDialog() {
    final nameCtrl = TextEditingController(text: _profile.name);
    final titleCtrl = TextEditingController(text: _profile.jobTitle);
    final compCtrl = TextEditingController(text: _profile.company);
    final phoneCtrl = TextEditingController(text: _profile.phone);
    final emailCtrl = TextEditingController(text: _profile.email);
    final webCtrl = TextEditingController(text: _profile.website);
    final addrCtrl = TextEditingController(text: _profile.address);
    final notesCtrl = TextEditingController(text: _profile.notes);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'My Expo Card Info',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _fieldInput('Full Name', nameCtrl, Icons.person_outline),
              _fieldInput('Job Title', titleCtrl, Icons.badge_outlined),
              _fieldInput('Company Name', compCtrl, Icons.business_outlined),
              _fieldInput('Phone Number', phoneCtrl, Icons.phone_outlined, keyboardType: TextInputType.phone),
              _fieldInput('Email Address', emailCtrl, Icons.email_outlined, keyboardType: TextInputType.emailAddress),
              _fieldInput('Website', webCtrl, Icons.language_outlined, keyboardType: TextInputType.url),
              _fieldInput('Address / City', addrCtrl, Icons.location_on_outlined),
              _fieldInput('Notes / Stall No.', notesCtrl, Icons.notes_outlined),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final newProfile = MyProfile(
                    name: nameCtrl.text.trim(),
                    jobTitle: titleCtrl.text.trim(),
                    company: compCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    website: webCtrl.text.trim(),
                    address: addrCtrl.text.trim(),
                    notes: notesCtrl.text.trim(),
                  );
                  await MyProfileStore.save(newProfile);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    setState(() => _profile = newProfile);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profile updated successfully!')),
                    );
                  }
                },
                child: const Text('Save & Update QR', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldInput(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Future<void> _shareVCard() async {
    if (_profile.isEmpty) return;
    final vcfText = _profile.toVCard();
    final tempDir = await getTemporaryDirectory();
    final safeName = (_profile.name.isNotEmpty ? _profile.name : 'my_expo_contact')
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final vcfFile = File('${tempDir.path}/$safeName.vcf');
    await vcfFile.writeAsString(vcfText);
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: 'My Contact: ${_profile.name} (${_profile.company})',
        files: [XFile(vcfFile.path)],
        subject: '$safeName.vcf',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final vcardData = _profile.toVCard();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F6),
      appBar: AppBar(
        title: const Text('My Expo QR', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Edit Profile',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _openEditDialog,
          ),
          IconButton(
            tooltip: 'Share Card',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: _profile.isEmpty ? null : _shareVCard,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              if (_profile.isEmpty)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        const Icon(Icons.qr_code_2, size: 72, color: Color(0xFF7390FF)),
                        const SizedBox(height: 16),
                        const Text(
                          'Set Up Your Expo QR Code',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Save your contact details once. Expo visitors and buyers can scan this QR with their smartphone camera to instantly add you to their contacts.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1C1C1E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: _openEditDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add My Details'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Card(
                  elevation: 4,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
                    child: Column(
                      children: [
                        if (_profile.company.isNotEmpty)
                          Text(
                            _profile.company.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: Color(0xFF7390FF),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _profile.name.isNotEmpty ? _profile.name : 'My Contact',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_profile.jobTitle.isNotEmpty)
                          Text(
                            _profile.jobTitle,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.black12, width: 1.5),
                          ),
                          child: QrImageView(
                            data: vcardData,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF1C1C1E),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF1C1C1E),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.camera_alt_outlined, size: 16, color: Colors.black54),
                            SizedBox(width: 6),
                            Text(
                              'Scan with camera to save contact',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Column(
                      children: [
                        if (_profile.phone.isNotEmpty)
                          _contactInfoRow(Icons.phone_outlined, _profile.phone),
                        if (_profile.email.isNotEmpty)
                          _contactInfoRow(Icons.email_outlined, _profile.email),
                        if (_profile.website.isNotEmpty)
                          _contactInfoRow(Icons.language_outlined, _profile.website),
                        if (_profile.address.isNotEmpty)
                          _contactInfoRow(Icons.location_on_outlined, _profile.address),
                        if (_profile.notes.isNotEmpty)
                          _contactInfoRow(Icons.notes_outlined, _profile.notes),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _openEditDialog,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit Card'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1C1E),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _shareVCard,
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share vCard'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF7390FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16, color: Colors.black45),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied: $text'), duration: const Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
    );
  }
}
