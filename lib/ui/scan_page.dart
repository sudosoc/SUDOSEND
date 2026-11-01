import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wraith_core/pairing.dart';

import '../app/scope.dart';
import 'glass.dart';
import 'theme.dart';

/// Full-screen camera that returns a SUDOSEND pairing link.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _lastInvalid;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      if (PairingInfo.tryParse(raw) != null) {
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
      if (raw != _lastInvalid) {
        _lastInvalid = raw;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('scan_invalid'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final box = (size.shortestSide * 0.68).clamp(200.0, 340.0);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          // Viewfinder
          Center(
            child: Container(
              width: box,
              height: box,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.cyan, width: 3),
                boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.45), blurRadius: 30)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Glass(
                        radius: 40,
                        padding: const EdgeInsets.all(10),
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.close_rounded, color: AppColors.text),
                      ),
                      const Spacer(),
                      Glass(
                        radius: 40,
                        padding: const EdgeInsets.all(10),
                        onTap: _scanner.toggleTorch,
                        child: const Icon(Icons.flashlight_on_rounded, color: AppColors.text),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Glass(
                    child: Column(
                      children: [
                        Text(context.tr('scan_title'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        const SizedBox(height: 6),
                        Text(context.tr('scan_hint'),
                            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
