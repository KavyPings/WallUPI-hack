import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController();
  bool _detected = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _detected = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _ScanOverlay(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(null),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Scan UPI QR Code',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 48,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Point camera at a UPI QR code',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final frameSize = size.width * 0.65;
    final left = (size.width - frameSize) / 2;
    final top = (size.height - frameSize) / 2;
    const radius = 12.0;
    const strokeLen = 28.0;
    const strokeWidth = 4.0;
    const color = Colors.white;

    return Stack(
      children: [
        // Semi-transparent overlay outside the scan frame
        ColorFiltered(
          colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcOut),
          child: Stack(
            children: [
              Container(color: Colors.transparent),
              Positioned(
                left: left,
                top: top,
                child: Container(
                  width: frameSize,
                  height: frameSize,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Corner brackets
        for (final corner in _CornerSpec.all(left, top, frameSize, radius, strokeLen))
          Positioned(
            left: corner.x,
            top: corner.y,
            child: CustomPaint(
              size: Size(strokeLen + radius, strokeLen + radius),
              painter: _CornerPainter(corner, strokeWidth, color),
            ),
          ),
      ],
    );
  }
}

enum _CornerType { topLeft, topRight, bottomLeft, bottomRight }

class _CornerSpec {
  final double x, y;
  final _CornerType type;
  const _CornerSpec(this.x, this.y, this.type);

  static List<_CornerSpec> all(
      double left, double top, double size, double radius, double len) {
    return [
      _CornerSpec(left - radius, top - radius, _CornerType.topLeft),
      _CornerSpec(left + size - len, top - radius, _CornerType.topRight),
      _CornerSpec(left - radius, top + size - len, _CornerType.bottomLeft),
      _CornerSpec(left + size - len, top + size - len, _CornerType.bottomRight),
    ];
  }
}

class _CornerPainter extends CustomPainter {
  final _CornerSpec spec;
  final double strokeWidth;
  final Color color;

  const _CornerPainter(this.spec, this.strokeWidth, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final r = size.width - (size.width - strokeWidth);
    const len = 28.0;

    switch (spec.type) {
      case _CornerType.topLeft:
        canvas.drawLine(Offset(strokeWidth / 2, len), Offset(strokeWidth / 2, strokeWidth / 2), paint);
        canvas.drawLine(Offset(strokeWidth / 2, strokeWidth / 2), Offset(len, strokeWidth / 2), paint);
      case _CornerType.topRight:
        canvas.drawLine(Offset(size.width - strokeWidth / 2, len), Offset(size.width - strokeWidth / 2, strokeWidth / 2), paint);
        canvas.drawLine(Offset(size.width - strokeWidth / 2, strokeWidth / 2), Offset(size.width - len, strokeWidth / 2), paint);
      case _CornerType.bottomLeft:
        canvas.drawLine(Offset(strokeWidth / 2, size.height - len), Offset(strokeWidth / 2, size.height - strokeWidth / 2), paint);
        canvas.drawLine(Offset(strokeWidth / 2, size.height - strokeWidth / 2), Offset(len, size.height - strokeWidth / 2), paint);
      case _CornerType.bottomRight:
        canvas.drawLine(Offset(size.width - strokeWidth / 2, size.height - len), Offset(size.width - strokeWidth / 2, size.height - strokeWidth / 2), paint);
        canvas.drawLine(Offset(size.width - strokeWidth / 2, size.height - strokeWidth / 2), Offset(size.width - len, size.height - strokeWidth / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
