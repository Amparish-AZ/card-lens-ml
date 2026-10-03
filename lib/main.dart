import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'card_parser.dart';
import 'camera_scanner_page.dart';
import 'contextual_verifier.dart';
import 'field_classifier.dart';
import 'mobile_ocr_service.dart';
import 'my_qr_page.dart';
import 'perspective_page.dart';
import 'saved_cards.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const CardLensApp());
}

const ink = Color(0xFF171719),
    blue = Color(0xFF343438),
    soft = Color(0x99FFFFFF);

class CardLensApp extends StatelessWidget {
  const CardLensApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'CardLens',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: blue),
      scaffoldBackgroundColor: const Color(0xFFE8E8EA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xAFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x99FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF77777D), width: 1.2),
        ),
      ),
    ),
    home: const BrandSplashPage(),
  );
}

class BrandSplashPage extends StatefulWidget {
  const BrandSplashPage({super.key});
  @override
  State<BrandSplashPage> createState() => _BrandSplashPageState();
}

class _BrandSplashPageState extends State<BrandSplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> fade;
  late final Animation<double> scale;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    fade = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    scale = Tween<double>(
      begin: .92,
      end: 1,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutBack));
    controller.forward();
    Future<void>.delayed(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, secondaryAnimation) => const HomePage(),
          transitionDuration: const Duration(milliseconds: 240),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF4F4F5), Color(0xFFD5D5D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: LayoutBuilder(
              builder: (context, constraints) => Image.asset(
                'assets/branding/lw_app_logo.png',
                width: MediaQuery.sizeOf(context).width * .55,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 45,
    height: 34,
    child: CustomPaint(painter: LwLogoPainter()),
  );
}

class LwLogoPainter extends CustomPainter {
  const LwLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final orange = Paint()..color = const Color(0xFFF79400);
    final lightGreen = Paint()..color = const Color(0xFF8DC63F);
    final green = Paint()..color = const Color(0xFF55B62C);
    canvas.drawPath(
      Path()
        ..moveTo(1, 2)
        ..lineTo(7, 2)
        ..lineTo(7, 25)
        ..lineTo(20, 25)
        ..lineTo(17, 32)
        ..lineTo(1, 32)
        ..close(),
      orange,
    );
    canvas.drawPath(
      Path()
        ..moveTo(12, 2)
        ..lineTo(19, 2)
        ..lineTo(31, 26)
        ..lineTo(27, 32)
        ..close(),
      lightGreen,
    );
    canvas.drawPath(
      Path()
        ..moveTo(22, 2)
        ..lineTo(29, 2)
        ..lineTo(39, 22)
        ..lineTo(35, 29)
        ..close(),
      green,
    );
    const dots = [
      Offset(35, 4),
      Offset(40, 4),
      Offset(44, 4),
      Offset(37.5, 9),
      Offset(42, 9),
      Offset(40, 14),
    ];
    for (final dot in dots) {
      canvas.drawCircle(dot, 1.7, green);
    }
  }

  @override
  bool shouldRepaint(LwLogoPainter oldDelegate) => false;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final picker = ImagePicker();
  bool working = false;
  Future<void> scan(ImageSource source) async {
    try {
      final XFile? image = source == ImageSource.camera
          ? await Navigator.push<XFile>(
              context,
              MaterialPageRoute(builder: (_) => const CameraScannerPage()),
            )
          : await picker.pickImage(source: source, imageQuality: 100);
      if (image == null || !mounted) return;
      var processingPath = image.path;
      if (source == ImageSource.gallery) {
        final cropped = await ImageCropper().cropImage(
          sourcePath: image.path,
          compressFormat: ImageCompressFormat.jpg,
          compressQuality: 96,
          maxWidth: 1800,
          maxHeight: 1800,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop business card',
              toolbarColor: const Color(0xFFF0F0F2),
              toolbarWidgetColor: ink,
              activeControlsWidgetColor: const Color(0xFF6A9BC8),
              initAspectRatio: CropAspectRatioPreset.original,
              lockAspectRatio: false,
            ),
            IOSUiSettings(
              title: 'Crop business card',
              doneButtonTitle: 'Use card',
              cancelButtonTitle: 'Cancel',
              aspectRatioLockEnabled: false,
              resetAspectRatioEnabled: true,
            ),
          ],
        );
        if (cropped == null || !mounted) return;
        final correctedPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => PerspectiveCorrectionPage(imagePath: cropped.path),
          ),
        );
        if (correctedPath == null || !mounted) return;
        processingPath = correctedPath;
      }
      setState(() => working = true);
      final result = await MobileOcrService().recognize(processingPath);
      if (!mounted) return;
      var cardData = await SmartBusinessCardParser.parse(
        result.text,
        layout: result.lines,
      );
      if (!mounted) return;
      setState(() => working = false);

      final wantBackSide = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7390FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.flip_to_back, color: Color(0xFF7390FF), size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Front side captured!',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Does this card have a back side to scan?',
                            style: TextStyle(color: Colors.black54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1C1C1E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => Navigator.pop(sheetCtx, true),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Scan Back Side', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => Navigator.pop(sheetCtx, false),
                  icon: const Icon(Icons.skip_next_outlined),
                  label: const Text('Skip & Review Front Only', style: TextStyle(fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
      );

      if (wantBackSide == true && mounted) {
        final XFile? backImage = source == ImageSource.camera
            ? await Navigator.push<XFile>(
                context,
                MaterialPageRoute(builder: (_) => const CameraScannerPage()),
              )
            : await picker.pickImage(source: source, imageQuality: 100);
        if (backImage != null && mounted) {
          setState(() => working = true);
          final backResult = await MobileOcrService().recognize(backImage.path);
          final backData = await SmartBusinessCardParser.parse(
            backResult.text,
            layout: backResult.lines,
          );
          cardData = BusinessCardData.merge(cardData, backData);
          setState(() => working = false);
        }
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ReviewPage(imagePath: result.previewPath, data: cardData),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is FormatException
                ? e.message
                : 'Could not scan this image. Check permission and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF4F4F5), Color(0xFFD7D7DA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            BrandMark(),
                            SizedBox(width: 10),
                            Text(
                              'CardLens',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          tooltip: 'My Expo QR',
                          icon: const Icon(Icons.qr_code_2, size: 30, color: Color(0xFF1C1C1E)),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const MyQrPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 50),
                    const Text(
                      'Scan a card',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Capture or choose a photo',
                      style: TextStyle(fontSize: 16, color: Color(0xFF6D6D72)),
                    ),
                    const SizedBox(height: 24),
                    const GlassPanel(
                      height: 180,
                      child: Center(
                        child: Icon(
                          Icons.contact_page_outlined,
                          size: 62,
                          color: Color(0xFF55555A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    actionButton(
                      Icons.camera_alt_outlined,
                      'Camera',
                      () => scan(ImageSource.camera),
                      true,
                    ),
                    const SizedBox(height: 10),
                    actionButton(
                      Icons.photo_library_outlined,
                      'Photos',
                      () => scan(ImageSource.gallery),
                      false,
                    ),
                    const SizedBox(height: 10),
                    actionButton(
                      Icons.folder_copy_outlined,
                      'Saved cards',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const SavedCardsPage(),
                        ),
                      ),
                      false,
                    ),
                    const SizedBox(height: 10),
                    actionButton(
                      Icons.qr_code_2,
                      'My Expo QR',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const MyQrPage(),
                        ),
                      ),
                      false,
                    ),
                  ],
                ),
              ],
            ),
            if (working)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xB3E8E8EA),
                  child: Center(
                    child: GlassPanel(
                      height: 120,
                      width: 170,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: ink,
                            ),
                          ),
                          SizedBox(height: 14),
                          Text(
                            'Processing…',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  Widget actionButton(
    IconData icon,
    String text,
    VoidCallback press,
    bool primary,
  ) => SizedBox(
    width: double.infinity,
    height: 56,
    child: primary
        ? FilledButton.icon(
            onPressed: working ? null : press,
            icon: Icon(icon),
            label: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB8D4EE),
              foregroundColor: const Color(0xFF203247),
              disabledBackgroundColor: const Color(0xFFCDDCE9),
              disabledForegroundColor: const Color(0xFF6E7E8E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          )
        : OutlinedButton.icon(
            onPressed: working ? null : press,
            icon: Icon(icon),
            label: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: ink,
              backgroundColor: const Color(0x73FFFFFF),
              side: const BorderSide(color: Color(0xB3FFFFFF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
  );
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.imagePath, required this.data});
  final String imagePath;
  final BusinessCardData data;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final Map<String, TextEditingController> fields;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final d = widget.data;
    fields = {
      'Full name': TextEditingController(text: d.name),
      'Job title': TextEditingController(text: d.jobTitle),
      'Company': TextEditingController(text: d.company),
      'Email': TextEditingController(text: d.email),
      'Phone': TextEditingController(text: d.phone),
      'Website': TextEditingController(text: d.website),
      'Address': TextEditingController(text: d.address),
      'Stall / Booth': TextEditingController(text: d.stall),
      'Notes': TextEditingController(text: d.notes),
    };
    for (var i = 0; i < d.additionalEmails.length; i++) {
      fields['Email ${i + 2}'] = TextEditingController(
        text: d.additionalEmails[i],
      );
    }
    for (var i = 0; i < d.additionalPhones.length; i++) {
      fields['Phone ${i + 2}'] = TextEditingController(
        text: d.additionalPhones[i],
      );
    }
    for (var i = 0; i < d.additionalWebsites.length; i++) {
      fields['Website ${i + 2}'] = TextEditingController(
        text: d.additionalWebsites[i],
      );
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  IconData icon(String label) => switch (label) {
    'Full name' => Icons.person_outline,
    'Job title' => Icons.badge_outlined,
    'Company' => Icons.business_outlined,
    'Stall / Booth' => Icons.storefront_outlined,
    'Notes' => Icons.edit_note_outlined,
    'Address' => Icons.location_on_outlined,
    _ when label.startsWith('Email') => Icons.mail_outline,
    _ when label.startsWith('Phone') => Icons.phone_outlined,
    _ when label.startsWith('Website') => Icons.language,
    _ => Icons.notes_outlined,
  };

  FieldValidation _getValidation(String key, String value) {
    return switch (key) {
      'Full name' => ContextualCardVerifier.verifyName(
        value,
        email: fields['Email']?.text ?? '',
      ),
      'Company' => ContextualCardVerifier.verifyCompany(
          value,
          email: fields['Email']?.text ?? '',
          website: fields['Website']?.text ?? '',
        ),
      'Job title' => value.trim().isNotEmpty
          ? const FieldValidation(level: VerificationLevel.verified, message: 'Recognized designation')
          : const FieldValidation(level: VerificationLevel.empty, message: 'No title on card'),
      'Phone' || 'Phone 2' || 'Phone 3' => ContextualCardVerifier.verifyPhone(value),
      'Email' || 'Email 2' => ContextualCardVerifier.verifyEmail(value),
      'Website' || 'Website 2' => ContextualCardVerifier.verifyWebsite(value),
      'Address' => ContextualCardVerifier.verifyAddress(value),
      'Stall / Booth' => ContextualCardVerifier.verifyStall(value),
      'Notes' => value.trim().isNotEmpty
          ? const FieldValidation(level: VerificationLevel.verified, message: 'Recorded notes')
          : const FieldValidation(level: VerificationLevel.empty, message: 'Optional notes'),
      _ => const FieldValidation(level: VerificationLevel.inferred, message: 'Custom field'),
    };
  }

  void _showAssignLineDialog(String text) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final assignable = [
          'Company',
          'Full name',
          'Job title',
          'Address',
          'Stall / Booth',
          'Notes',
          'Phone',
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assign detected text:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    text,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: assignable.map((targetField) {
                    return ActionChip(
                      avatar: Icon(icon(targetField), size: 16),
                      label: Text(targetField),
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          if (fields.containsKey(targetField)) {
                            fields[targetField]!.text = text;
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Review details',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
      children: [
        GlassPanel(
          height: 150,
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.file(
              File(widget.imagePath),
              fit: BoxFit.cover,
              width: double.infinity,
              cacheWidth: 1200,
            ),
          ),
        ),
        if (widget.data.rawText.contains('--- BACK ---')) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF34C759), width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flip_to_back, size: 14, color: Color(0xFF34C759)),
                    SizedBox(width: 6),
                    Text(
                      'Double-Sided: Front + Back Merged',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B8A3C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        ...fields.entries.map(
          (e) {
            final validation = _getValidation(e.key, e.value.text);
            return Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: TextField(
                controller: e.value,
                onChanged: (_) => setState(() {}),
                minLines: e.key == 'Address' || e.key == 'Notes' ? 2 : 1,
                maxLines: e.key == 'Address' || e.key == 'Notes' ? 3 : 1,
                keyboardType: e.key.startsWith('Email')
                    ? TextInputType.emailAddress
                    : e.key.startsWith('Phone')
                    ? TextInputType.phone
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: e.key,
                  prefixIcon: Icon(icon(e.key), size: 21),
                  suffixIcon: validation.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                validation.isVerified
                                    ? Icons.verified
                                    : (validation.isInferred
                                        ? Icons.info_outline
                                        : Icons.warning_amber_rounded),
                                size: 17,
                                color: validation.isVerified
                                    ? const Color(0xFF2E7D32)
                                    : (validation.isInferred
                                        ? const Color(0xFFE65100)
                                        : const Color(0xFFC62828)),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                validation.isVerified
                                    ? 'Verified'
                                    : (validation.isInferred
                                        ? 'Review'
                                        : 'Check'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: validation.isVerified
                                      ? const Color(0xFF2E7D32)
                                      : (validation.isInferred
                                          ? const Color(0xFFE65100)
                                          : const Color(0xFFC62828)),
                                ),
                              ),
                            ],
                          ),
                        ),
                  helperText: validation.isEmpty ? null : validation.message,
                  helperStyle: TextStyle(
                    fontSize: 11,
                    color: validation.isVerified
                        ? const Color(0xFF2E7D32)
                        : (validation.isInferred
                            ? const Color(0xFF757575)
                            : const Color(0xFFC62828)),
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.data.rawText.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.touch_app_outlined, size: 18, color: Color(0xFF55555A)),
              const SizedBox(width: 6),
              Text(
                'Detected text lines (Tap to assign)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.data.rawText
                .split(RegExp(r'[\r\n]+'))
                .map((l) => l.trim())
                .where((l) => l.length > 1)
                .toSet()
                .map(
                  (line) => ActionChip(
                    label: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade300),
                    onPressed: () => _showAssignLineDialog(line),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ],
        const SizedBox(height: 3),
        SizedBox(
          height: 55,
          child: FilledButton.icon(
            onPressed: saving ? null : saveCard,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E2E31),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text(
              'Save contact',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ),
  );
  Future<void> saveCard() async {
    setState(() => saving = true);
    try {
      await SavedCardStore.save(
        sourceImagePath: widget.imagePath,
        fields: fields.map((key, value) => MapEntry(key, value.text.trim())),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Card saved')));
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save this card')));
    }
  }

  void showRaw() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recognized text',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.data.rawText,
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SavedCardsPage extends StatefulWidget {
  const SavedCardsPage({super.key});
  @override
  State<SavedCardsPage> createState() => _SavedCardsPageState();
}

class _SavedCardsPageState extends State<SavedCardsPage> {
  late Future<List<SavedCard>> cards;
  final searchController = TextEditingController();
  String query = '';

  @override
  void initState() {
    super.initState();
    cards = SavedCardStore.load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void reload() => setState(() => cards = SavedCardStore.load());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Saved cards',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Export All to Excel / CSV',
          icon: const Icon(Icons.table_view_outlined),
          onPressed: () async {
            final cardList = await cards;
            if (!context.mounted) return;
            if (cardList.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No saved cards to export.')),
              );
              return;
            }
            final file = await SavedCardStore.writeCsvFile(cardList);
            if (!context.mounted) return;
            final box = context.findRenderObject() as RenderBox?;
            await SharePlus.instance.share(
              ShareParams(
                text: 'Exported ${cardList.length} business cards from CardLens',
                files: [XFile(file.path)],
                subject: file.uri.pathSegments.last,
                sharePositionOrigin: box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              ),
            );
          },
        ),
      ],
    ),
    body: FutureBuilder<List<SavedCard>>(
      future: cards,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: ink));
        }
        final allItems = snapshot.data!;
        final q = query.trim().toLowerCase();
        final items = q.isEmpty
            ? allItems
            : allItems.where((c) {
                return c.title.toLowerCase().contains(q) ||
                    c.fields.values.any((v) => v.toLowerCase().contains(q));
              }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: TextField(
                controller: searchController,
                onChanged: (text) => setState(() => query = text),
                decoration: InputDecoration(
                  hintText: 'Search by name, company, stall, phone…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            searchController.clear();
                            setState(() => query = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            allItems.isEmpty ? Icons.folder_open_outlined : Icons.search_off_outlined,
                            size: 54,
                            color: const Color(0xFF77777D),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            allItems.isEmpty ? 'No saved cards' : 'No matching cards found',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final card = items[index];
                        final stall = card.fields['Stall / Booth'];
                        return GlassPanel(
                          padding: const EdgeInsets.all(10),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(card.imagePath),
                                width: 72,
                                height: 58,
                                fit: BoxFit.cover,
                                cacheWidth: 220,
                                errorBuilder: (_, _, _) => const SizedBox(
                                  width: 72,
                                  child: Icon(Icons.image_not_supported_outlined),
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    card.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                if (stall != null && stall.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFB8D4EE),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      stall,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF203247),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              card.fields['Company']?.isNotEmpty == true
                                  ? card.fields['Company']!
                                  : (card.fields['Phone'] ?? card.fields['Email'] ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SavedCardDetailPage(card: card),
                              ),
                            ).then((_) => reload()),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class SavedCardDetailPage extends StatelessWidget {
  const SavedCardDetailPage({super.key, required this.card});
  final SavedCard card;

  Future<void> share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: card.shareText,
        files: [XFile(card.imagePath)],
        subject: card.title,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> exportVCard(BuildContext context) async {
    final vcfText = card.toVCard();
    final tempDir = await getTemporaryDirectory();
    final safeName = card.title.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final vcfFile = File('${tempDir.path}/$safeName.vcf');
    await vcfFile.writeAsString(vcfText);
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Contact: ${card.title}',
        files: [XFile(vcfFile.path)],
        subject: '$safeName.vcf',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> exportCsv(BuildContext context) async {
    final safeName = card.title.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final file = await SavedCardStore.writeCsvFile([card], filename: safeName);
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Contact: ${card.title}',
        files: [XFile(file.path)],
        subject: file.uri.pathSegments.last,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete card?'),
        content: const Text(
          'The saved image and extracted details will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SavedCardStore.delete(card);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        card.title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Export to Excel / CSV',
          onPressed: () => exportCsv(context),
          icon: const Icon(Icons.table_view_outlined),
        ),
        IconButton(
          tooltip: 'Export vCard',
          onPressed: () => exportVCard(context),
          icon: const Icon(Icons.contact_phone_outlined),
        ),
        IconButton(
          tooltip: 'Share',
          onPressed: () => share(context),
          icon: const Icon(Icons.ios_share_outlined),
        ),
        IconButton(
          tooltip: 'Delete',
          onPressed: () => delete(context),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
      children: [
        GlassPanel(
          height: 210,
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.file(
              File(card.imagePath),
              fit: BoxFit.contain,
              cacheWidth: 1400,
            ),
          ),
        ),
        const SizedBox(height: 18),
        ...card.fields.entries
            .where((entry) => entry.value.isNotEmpty)
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassPanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6D6D72),
                        ),
                      ),
                      const SizedBox(height: 3),
                      SelectableText(
                        entry.value,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => exportVCard(context),
                icon: const Icon(Icons.contact_phone_outlined),
                label: const Text('Export vCard'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB8D4EE),
                  foregroundColor: const Color(0xFF203247),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => share(context),
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => delete(context),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
            ),
          ],
        ),
      ],
    ),
  );
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.height,
    this.width,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final double? height, width;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: width ?? double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: const Color(0xB8FFFFFF),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xE6FFFFFF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 16,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: child,
  );
}
