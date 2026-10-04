import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A banner-ribbon header widget used in dialogs and headers.
/// Features a front banner with gold borders, folded shadow triangles,
/// and notched ribbon tails sticking out on both sides.
class RibbonHeader extends StatelessWidget {
  final String title;
  final double bannerWidth;
  final double height;
  final double fontSize;
  final LinearGradient? gradient;
  final Color? tailColor;

  const RibbonHeader({
    super.key,
    required this.title,
    double? width,
    double bannerWidth = 270,
    this.height = 46,
    this.fontSize = 18,
    this.gradient,
    this.tailColor,
  }) : bannerWidth = width ?? bannerWidth;

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFFFD15C);
    const goldDark = Color(0xFFC99824);
    const purpleMain = Color(0xFF8B3EE8);
    const purpleDark = Color(0xFF5B1AA8);
    final backTailColor = tailColor ?? const Color(0xFF6B24BF);
    final foldShadowColor = const Color(0xFF240A48);

    final bannerGradient = gradient ??
        const LinearGradient(
          colors: [purpleMain, Color(0xFF7524DB), purpleDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );

    const tailWidth = 28.0;
    const tailHeightOffset = 6.0;
    final totalWidth = bannerWidth + tailWidth * 2;
    final totalHeight = height + tailHeightOffset + 2;

    return SizedBox(
      width: totalWidth,
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // ── Left Tail (behind banner) ─────────────────────────────
          Positioned(
            left: 0,
            top: tailHeightOffset,
            child: CustomPaint(
              size: Size(tailWidth + 6, height),
              painter: _RibbonTailPainter(
                isLeft: true,
                tailColor: backTailColor,
                goldColor: goldColor,
                goldDark: goldDark,
                shadowColor: foldShadowColor,
              ),
            ),
          ),

          // ── Right Tail (behind banner) ────────────────────────────
          Positioned(
            right: 0,
            top: tailHeightOffset,
            child: CustomPaint(
              size: Size(tailWidth + 6, height),
              painter: _RibbonTailPainter(
                isLeft: false,
                tailColor: backTailColor,
                goldColor: goldColor,
                goldDark: goldDark,
                shadowColor: foldShadowColor,
              ),
            ),
          ),

          // ── Main Center Banner ────────────────────────────────────
          Positioned(
            top: 0,
            child: Container(
              width: bannerWidth,
              height: height,
              decoration: BoxDecoration(
                gradient: bannerGradient,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: const Border(
                  top: BorderSide(color: goldColor, width: 2.4),
                  bottom: BorderSide(color: goldDark, width: 2.4),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2.5,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      offset: const Offset(0, 2),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function for backward-compatibility with existing screens
Widget buildRibbonHeader(String title) {
  return RibbonHeader(title: title);
}

class _RibbonTailPainter extends CustomPainter {
  final bool isLeft;
  final Color tailColor;
  final Color goldColor;
  final Color goldDark;
  final Color shadowColor;

  const _RibbonTailPainter({
    required this.isLeft,
    required this.tailColor,
    required this.goldColor,
    required this.goldDark,
    required this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillPaint = Paint()
      ..color = tailColor
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = shadowColor
      ..style = PaintingStyle.fill;

    final topGoldPaint = Paint()
      ..color = goldColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    final bottomGoldPaint = Paint()
      ..color = goldDark
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    final tailPath = Path();

    if (isLeft) {
      // Tail sticking out to the left
      // Outer V-notch on left: (0, 0) -> (10, h/2) -> (0, h)
      tailPath.moveTo(0, 0);
      tailPath.lineTo(w, 0);
      tailPath.lineTo(w, h);
      tailPath.lineTo(0, h);
      tailPath.lineTo(10, h / 2);
      tailPath.close();
      canvas.drawPath(tailPath, fillPaint);

      // Gold borders
      canvas.drawLine(const Offset(0, 1), Offset(w, 1), topGoldPaint);
      canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), bottomGoldPaint);

      // Fold shadow triangle where banner folds over tail at top
      final foldPath = Path()
        ..moveTo(w - 6, 0)
        ..lineTo(w, 0)
        ..lineTo(w - 6, -6)
        ..close();
      canvas.drawPath(foldPath, shadowPaint);
    } else {
      // Tail sticking out to the right
      // Outer V-notch on right: (w, 0) -> (w - 10, h/2) -> (w, h)
      tailPath.moveTo(0, 0);
      tailPath.lineTo(w, 0);
      tailPath.lineTo(w - 10, h / 2);
      tailPath.lineTo(w, h);
      tailPath.lineTo(0, h);
      tailPath.close();
      canvas.drawPath(tailPath, fillPaint);

      // Gold borders
      canvas.drawLine(const Offset(0, 1), Offset(w, 1), topGoldPaint);
      canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), bottomGoldPaint);

      // Fold shadow triangle where banner folds over tail at top
      final foldPath = Path()
        ..moveTo(0, 0)
        ..lineTo(6, 0)
        ..lineTo(6, -6)
        ..close();
      canvas.drawPath(foldPath, shadowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

