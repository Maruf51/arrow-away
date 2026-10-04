import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _progressController.forward();
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/menu');
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.1),
            radius: 1.1,
            colors: [
              Color(0xFF261247),
              Color(0xFF140728),
              Color(0xFF0D031D),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Floating background dots (gold and muted dots)
            const _SplashBackgroundDots(),

            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── App Icon / Logo with surrounding arrows ───────────────
                  _buildLogoWithSurroundingArrows()
                      .animate(delay: 150.ms)
                      .fadeIn(duration: 500.ms)
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1.0, 1.0),
                        curve: Curves.easeOutBack,
                      ),

                  const SizedBox(height: 28),

                  // ── "ARROW AWAY" title ───────────────────────────────────
                  Text(
                    'ARROW AWAY',
                    style: GoogleFonts.nunito(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFFD45E),
                      letterSpacing: 2.5,
                      shadows: [
                        Shadow(
                          color: const Color(0xFFFFA800).withValues(alpha: 0.6),
                          blurRadius: 18,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  )
                      .animate(delay: 300.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.25, end: 0),

                  const SizedBox(height: 12),

                  // ── "★ TAP PUZZLE ★" badge ──────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9845EA), Color(0xFF7020CA)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFFFD15C),
                        width: 1.6,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7020CA).withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      '★ TAP PUZZLE ★',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  )
                      .animate(delay: 450.ms)
                      .fadeIn(duration: 400.ms)
                      .scale(begin: const Offset(0.85, 0.85)),

                  const SizedBox(height: 58),

                  // ── Loading subtitle ─────────────────────────────────────
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, _) {
                      final p = _progressController.value;
                      final label = p < 0.4
                          ? 'Crafting puzzle boards... 🧩'
                          : p < 0.85
                              ? 'Polishing arrows... 🎯'
                              : 'Ready to play! 🚀';
                      return Text(
                        label,
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFDCC8FF),
                          letterSpacing: 0.5,
                        ),
                      );
                    },
                  ).animate(delay: 600.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 14),

                  // ── Pill Loading Bar with % inside ───────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 46),
                    child: AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, _) {
                        final progress = CurvedAnimation(
                          parent: _progressController,
                          curve: Curves.easeInOut,
                        ).value;
                        final percentInt = (progress * 100).toInt();

                        return Container(
                          height: 18,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B0B33),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF5D24A6),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6B29D4)
                                    .withValues(alpha: 0.3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Filled track
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: progress.clamp(0.02, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFA65BF8),
                                          Color(0xFF7B26E0),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFA65BF8)
                                              .withValues(alpha: 0.7),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Percentage text in the center
                              Text(
                                '$percentInt%',
                                style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFB57BF8),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ).animate(delay: 700.ms).fadeIn(duration: 500.ms),

                  const SizedBox(height: 16),

                  // ── "GET READY..." text ──────────────────────────────────
                  Text(
                    'GET READY...',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFC79836),
                      letterSpacing: 2.5,
                    ),
                  ).animate(delay: 850.ms).fadeIn(duration: 400.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoWithSurroundingArrows() {
    return SizedBox(
      width: 180,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Upper-right floating arrow (khaki/gold)
          Positioned(
            top: 2,
            right: 64,
            child: Transform.rotate(
              angle: 0.25,
              child: const Icon(
                Icons.navigation_rounded,
                color: Color(0xFF9E7C3E),
                size: 26,
              ),
            ),
          ),

          // Mid-left floating arrow (teal/green)
          Positioned(
            left: 20,
            top: 56,
            child: Transform.rotate(
              angle: -0.7,
              child: const Icon(
                Icons.navigation_rounded,
                color: Color(0xFF4FA88C),
                size: 24,
              ),
            ),
          ),

          // Lower-right floating arrow (cyan/blue)
          Positioned(
            right: 22,
            bottom: 42,
            child: Transform.rotate(
              angle: 0.95,
              child: const Icon(
                Icons.navigation_rounded,
                color: Color(0xFF3B8EB8),
                size: 24,
              ),
            ),
          ),

          // Center Logo Squircle
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFDF7A), Color(0xFFC89324)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD45E).withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 3,
                ),
              ],
            ),
            padding: const EdgeInsets.all(4.5),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                gradient: const RadialGradient(
                  center: Alignment.center,
                  radius: 0.75,
                  colors: [
                    Color(0xFF6B22C7),
                    Color(0xFF380C75),
                    Color(0xFF22054D),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFF7E32E0),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      colors: [Color(0xFFFFF7C2), Color(0xFFFFCC33)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ).createShader(bounds);
                  },
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    color: Colors.white,
                    size: 58,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashBackgroundDots extends StatelessWidget {
  const _SplashBackgroundDots();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final rng = math.Random(1234);

    return Stack(
      children: List.generate(18, (i) {
        final x = rng.nextDouble() * size.width;
        final y = rng.nextDouble() * size.height;
        final r = rng.nextDouble() * 3.5 + 2.0;
        final isGold = i % 2 == 0;

        return Positioned(
          left: x,
          top: y,
          child: Container(
            width: r,
            height: r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isGold
                  ? const Color(0xFFC59B3F).withValues(alpha: 0.5)
                  : const Color(0xFF7E42C9).withValues(alpha: 0.35),
            ),
          ),
        );
      }),
    );
  }
}
