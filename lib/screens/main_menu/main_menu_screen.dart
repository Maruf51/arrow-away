import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/level_repository.dart';
import '../../widgets/unified_banner_ad.dart';
import '../../widgets/ribbon_header.dart';
import '../../widgets/shop_dialog.dart';
import '../../widgets/developer_menu_dialog.dart';
import '../settings/settings_screen.dart';
import '../../core/audio_manager.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  bool _isNavigating = false;
  int _titleTapCount = 0;
  Timer? _titleTapReset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProgressRepository>().recordDailyPlay();
      _preWarmLevels();
      _checkPlayStoreUpdate();
    });
  }

  @override
  void dispose() {
    _titleTapReset?.cancel();
    super.dispose();
  }

  void _handleTitleTap() {
    _titleTapReset?.cancel();
    _titleTapCount++;
    _titleTapReset = Timer(const Duration(seconds: 2), () {
      _titleTapCount = 0;
    });
    if (_titleTapCount < 10) return;

    _titleTapCount = 0;
    _titleTapReset?.cancel();
    AudioManager.instance.playClick();
    _showDeveloperMenu();
  }

  Future<void> _showDeveloperMenu() async {
    final action = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => const DeveloperMenuDialog(),
    );
    if (!mounted || action == null) return;
    final level = action['level'];
    if (level == null) return;

    setState(() => _isNavigating = true);
    await Navigator.pushNamed(
      context,
      '/game',
      arguments: {
        'level': level,
        if (action.containsKey('gridSize'))
          'sandboxGridSize': action['gridSize'],
      },
    );
    if (mounted) setState(() => _isNavigating = false);
  }

  void _preWarmLevels() {
    final progress = context.read<ProgressRepository>();
    final levelRepo = context.read<LevelRepository>();
    final currentLevel = progress.currentLevel;
    for (int i = 0; i < 4; i++) {
      levelRepo.preGenerateAsync(currentLevel + i);
    }
  }

  Future<void> _checkPlayStoreUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (e) {
      debugPrint('Play Store update check failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressRepository>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF261247),
              Color(0xFF1E0E3B),
              Color(0xFF14082B),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Background puzzle grid with subtle pluses and dots
            const Positioned.fill(
              child: _GridBackgroundPattern(),
            ),

            // Background floating 3D stylized arrows
            const Positioned.fill(
              child: _BackgroundArrowsPattern(),
            ),

            SafeArea(
              child: Column(
                children: [
                  // ── Top Bar ──────────────────────────────────────────────
                  _buildTopBar(context, progress),

                  const Spacer(flex: 3),

                  // ── Title "ARROW AWAY" ───────────────────────────────────
                  _buildTitle(progress),

                  const SizedBox(height: 12),

                  // ── Ribbon under title ───────────────────────────────────
                  const RibbonHeader(
                    title: 'ARROW AWAY',
                    width: 220,
                    height: 38,
                    fontSize: 15,
                  ).animate(delay: 200.ms).fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0),

                  const Spacer(flex: 2),

                  // ── 1. Big Green PLAY NOW Button ─────────────────────────
                  _buildPlayNowButton(context, progress),

                  const SizedBox(height: 14),

                  // ── 2. Purple ALL LEVELS Button ──────────────────────────
                  _buildActionGameButton(
                    label: 'ALL LEVELS',
                    prefixIcon: Icons.grid_view_rounded,
                    suffixIcon: Icons.grid_view_rounded,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9E54FF), Color(0xFF7825E6)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    shadowColor: const Color(0xFF5615B3),
                    onTap: () {
                      AudioManager.instance.playClick();
                      Navigator.pushNamed(context, '/levels');
                    },
                  ),

                  const SizedBox(height: 12),

                  // ── 3. Golden Yellow SHOP Button ─────────────────────────
                  _buildActionGameButton(
                    label: 'SHOP',
                    prefixEmoji: '🛒',
                    suffixEmoji: '🛒',
                    textColor: const Color(0xFF382006),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFC738), Color(0xFFF09B16)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    shadowColor: const Color(0xFFB56A00),
                    onTap: () {
                      AudioManager.instance.playClick();
                      ShopDialog.show(context, initialTab: 1);
                    },
                  ),

                  const SizedBox(height: 12),

                  // ── 4. Purple SKIN SHOWCASE Button ───────────────────────
                  _buildActionGameButton(
                    label: 'SKIN SHOWCASE',
                    prefixEmoji: '🎨',
                    suffixEmoji: '🏹',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9E54FF), Color(0xFF7825E6)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    shadowColor: const Color(0xFF5615B3),
                    onTap: () {
                      AudioManager.instance.playClick();
                      ShopDialog.show(context, initialTab: 0);
                    },
                  ),

                  const Spacer(flex: 3),

                  // ── Bottom circular action icons ─────────────────────────
                  _buildBottomCirclesRow(context, progress),

                  const SizedBox(height: 10),

                  // ── Banner Ad ────────────────────────────────────────────
                  Container(
                    alignment: Alignment.center,
                    width: double.infinity,
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 6),
                    child: const UnifiedBannerAd(
                      admobUnitId: AppConstants.admobBannerUnitId,
                      unityPlacementId: AppConstants.unityBannerAdId,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ProgressRepository progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Purple Circular Settings Icon
          _PurpleCircleIconButton(
            icon: Icons.settings,
            onTap: () {
              AudioManager.instance.playClick();
              SettingsDialog.show(context);
            },
          ),
          const SizedBox(width: 10),
          // Purple Circular Calendar Icon
          _PurpleCircleIconButton(
            icon: Icons.calendar_month_rounded,
            onTap: () {
              AudioManager.instance.playClick();
              _showComingSoon(context, 'Daily Rewards');
            },
          ),
          const Spacer(),
          // Gold Coin Pill
          _ResourcePill(
            icon: Icons.monetization_on_rounded,
            iconColor: const Color(0xFFFFD45E),
            value: _formatNumber(progress.coins),
            borderColor: const Color(0xFFD89B1F),
            valueColor: const Color(0xFFFFE082),
            onAddTap: () {
              AudioManager.instance.playClick();
              ShopDialog.show(context, initialTab: 1);
            },
          ),
          const SizedBox(width: 10),
          // Pink Heart Pill
          _ResourcePill(
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFFF4D79),
            value: '${progress.lives}/${progress.maxLives}',
            borderColor: const Color(0xFFD83264),
            valueColor: Colors.white,
            onAddTap: () {
              AudioManager.instance.playClick();
              ShopDialog.show(context, initialTab: 2);
            },
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n < 1000) return '$n';
    return n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  Widget _buildTitle(ProgressRepository progress) {
    return GestureDetector(
      onTap: _handleTitleTap,
      onLongPress: () {
        HapticFeedback.heavyImpact();
        progress.toggleDemoMode();
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              progress.isDemoMode
                  ? '🚀 DEMO MODE ACTIVATED!'
                  : 'DEMO MODE DEACTIVATED',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor:
                progress.isDemoMode ? const Color(0xFFE67E22) : Colors.grey[800],
            duration: const Duration(seconds: 3),
          ),
        );
      },
      child: Column(
        children: [
          Text(
            'ARROW',
            style: GoogleFonts.nunito(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFFFD45E),
              height: 0.95,
              letterSpacing: 3,
              shadows: [
                Shadow(
                  color: const Color(0xFFFFA800).withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          Text(
            'AWAY',
            style: GoogleFonts.nunito(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 0.95,
              letterSpacing: 3,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          if (progress.isDemoMode)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE67E22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'DEMO MODE ACTIVE',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
        ],
      ),
    )
        .animate()
        .scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1.0, 1.0),
          duration: 500.ms,
          curve: Curves.elasticOut,
        );
  }

  Widget _buildPlayNowButton(
      BuildContext context, ProgressRepository progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _isNavigating
            ? null
            : () async {
                AudioManager.instance.playClick();
                if (!mounted) return;
                setState(() => _isNavigating = true);
                await Navigator.pushNamed(
                  context,
                  '/game',
                  arguments: {'level': progress.currentLevel},
                );
                if (mounted) setState(() => _isNavigating = false);
              },
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2ED573), Color(0xFF1E9C52)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF68EE9F),
              width: 2.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF15733C),
                offset: const Offset(0, 5),
                blurRadius: 0,
              ),
              BoxShadow(
                color: const Color(0xFF2ED573).withValues(alpha: 0.5),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              // LVL badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF136636),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'LVL ${progress.currentLevel}',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFD4FFE2),
                  ),
                ),
              ),

              // PLAY NOW text
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'PLAY NOW',
                      style: GoogleFonts.nunito(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFFFFD45E),
                      size: 24,
                    ),
                  ],
                ),
              ),

              // Right circle with play icon
              Container(
                margin: const EdgeInsets.only(right: 8),
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF136636),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionGameButton({
    required String label,
    IconData? prefixIcon,
    IconData? suffixIcon,
    String? prefixEmoji,
    String? suffixEmoji,
    required Gradient gradient,
    required Color shadowColor,
    Color textColor = Colors.white,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                offset: const Offset(0, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (prefixIcon != null) ...[
                Icon(prefixIcon, color: textColor, size: 18),
                const SizedBox(width: 8),
              ] else if (prefixEmoji != null) ...[
                Text(prefixEmoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  letterSpacing: 1.5,
                ),
              ),
              if (suffixIcon != null) ...[
                const SizedBox(width: 8),
                Icon(suffixIcon, color: textColor, size: 18),
              ] else if (suffixEmoji != null) ...[
                const SizedBox(width: 8),
                Text(suffixEmoji, style: const TextStyle(fontSize: 16)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomCirclesRow(
      BuildContext context, ProgressRepository progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 1. Speaker/Sound — MASTER audio toggle: one tap mutes (and
          //    resumes) both the sound effects and the background music.
          _PurpleCircleIconButton(
            icon: (progress.soundEnabled || progress.musicEnabled)
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            size: 48,
            iconSize: 22,
            onTap: () {
              final audioOn = progress.soundEnabled || progress.musicEnabled;
              if (audioOn) {
                // Muting: let this click be heard, then shut everything off.
                AudioManager.instance.playClick();
                progress.setSoundEnabled(false);
                progress.setMusicEnabled(false); // stops the bgm immediately
              } else {
                // Unmuting: restore both first so the confirmation click plays.
                progress.setSoundEnabled(true);
                progress.setMusicEnabled(true); // resumes the bgm
                AudioManager.instance.playClick();
              }
            },
          ),
          // 2. Vibration/Haptic (no Material "off" glyph exists for this one)
          _PurpleCircleIconButton(
            icon: Icons.vibration_rounded,
            size: 48,
            iconSize: 22,
            onTap: () {
              AudioManager.instance.playClick();
              progress.setVibrationEnabled(!progress.vibrationEnabled);
            },
          ),
          // 3. Question mark Help / How to play
          _PurpleCircleIconButton(
            icon: Icons.help_outline_rounded,
            size: 48,
            iconSize: 22,
            onTap: () {
              AudioManager.instance.playClick();
              _showHowToPlay(context);
            },
          ),
          // 4. Settings
          _PurpleCircleIconButton(
            icon: Icons.settings,
            size: 48,
            iconSize: 22,
            onTap: () {
              AudioManager.instance.playClick();
              SettingsDialog.show(context);
            },
          ),
        ],
      ),
    );
  }

  void _showHowToPlay(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => const HowToPlayDialog(),
    );
  }

  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$title coming soon!',
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF7B26E0),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ── Top Bar / Bottom Row Circular Button with White Ring ─────────────────────
class _PurpleCircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const _PurpleCircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF8F46E8), Color(0xFF6C28C7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.8),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5615B3).withValues(alpha: 0.6),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}

// ── Resource Counter Pill (Coins & Hearts) ───────────────────────────────────
class _ResourcePill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final Color borderColor;
  final Color valueColor;
  final VoidCallback onAddTap;

  const _ResourcePill({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.borderColor,
    required this.valueColor,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 8, right: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1B0B33),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 17),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onAddTap,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF00BFA5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Subtle Background Cross / Dot Grid ───────────────────────────────────────
class _GridBackgroundPattern extends StatelessWidget {
  const _GridBackgroundPattern();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPatternPainter(),
    );
  }
}

class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 48.0;
    final dotPaint = Paint()
      ..color = const Color(0xFF5A3E8A).withValues(alpha: 0.25)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.fill;

    final crossPaint = Paint()
      ..color = const Color(0xFF6B4CA3).withValues(alpha: 0.3)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    int rowIndex = 0;
    for (double y = spacing; y < size.height; y += spacing) {
      int colIndex = 0;
      for (double x = spacing / 2; x < size.width; x += spacing) {
        if ((rowIndex + colIndex) % 2 == 0) {
          // Cross +
          const crossSize = 4.0;
          canvas.drawLine(Offset(x - crossSize, y), Offset(x + crossSize, y), crossPaint);
          canvas.drawLine(Offset(x, y - crossSize), Offset(x, y + crossSize), crossPaint);
        } else {
          // Dot ·
          canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
        }
        colIndex++;
      }
      rowIndex++;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Background Floating 3D Stylized Arrows ──────────────────────────────────
class _BackgroundArrowsPattern extends StatelessWidget {
  const _BackgroundArrowsPattern();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        // Blue arrow pointing right (upper left)
        Positioned(
          left: 12,
          top: size.height * 0.20,
          child: _StylizedArrow(
            direction: AxisDirection.right,
            color: const Color(0xFF2196F3),
            length: 54,
          ),
        ),

        // Tan/Brown arrow pointing down (upper right)
        Positioned(
          right: 38,
          top: size.height * 0.16,
          child: _StylizedArrow(
            direction: AxisDirection.down,
            color: const Color(0xFF9E7C3E),
            length: 56,
          ),
        ),

        // Teal arrow pointing up/left (mid left, cut by edge)
        Positioned(
          left: 16,
          top: size.height * 0.51,
          child: _StylizedArrow(
            direction: AxisDirection.up,
            color: const Color(0xFF389679),
            length: 44,
          ),
        ),

        // Purple arrow pointing right (lower left)
        Positioned(
          left: 24,
          top: size.height * 0.76,
          child: _StylizedArrow(
            direction: AxisDirection.right,
            color: const Color(0xFF5D4099),
            length: 50,
          ),
        ),

        // Tan/Gold block pointing up (lower right)
        Positioned(
          right: 48,
          top: size.height * 0.74,
          child: Container(
            width: 18,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF8B6C35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}

class _StylizedArrow extends StatelessWidget {
  final AxisDirection direction;
  final Color color;
  final double length;

  const _StylizedArrow({
    required this.direction,
    required this.color,
    required this.length,
  });

  @override
  Widget build(BuildContext context) {
    double angle = 0;
    switch (direction) {
      case AxisDirection.up:
        angle = 0;
        break;
      case AxisDirection.right:
        angle = math.pi / 2;
        break;
      case AxisDirection.down:
        angle = math.pi;
        break;
      case AxisDirection.left:
        angle = -math.pi / 2;
        break;
    }

    return Transform.rotate(
      angle: angle,
      child: CustomPaint(
        size: Size(26, length),
        painter: _ArrowShapePainter(color: color),
      ),
    );
  }
}

class _ArrowShapePainter extends CustomPainter {
  final Color color;
  const _ArrowShapePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    // Arrow tip
    path.moveTo(w / 2, 0);
    path.lineTo(w, w * 0.7);
    path.lineTo(w * 0.68, w * 0.7);
    // Shaft
    path.lineTo(w * 0.68, h);
    path.lineTo(w * 0.32, h);
    path.lineTo(w * 0.32, w * 0.7);
    path.lineTo(0, w * 0.7);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── HOW TO PLAY DIALOG ────────────────────────────────────────────────────────
class HowToPlayDialog extends StatelessWidget {
  const HowToPlayDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Main cream card body
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9EE),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 36, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Master the arrows & mechanics',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6B5885),
                  ),
                ),
                const SizedBox(height: 14),

                // 1. Tap Clear Arrows
                _buildCard(
                  iconBg: const Color(0xFFE8D7FF),
                  icon: Icons.navigation_rounded,
                  iconColor: const Color(0xFF7E38E6),
                  title: 'Tap Clear Arrows',
                  description:
                      'Arrows fly straight in the exact direction they point. Tap an arrow only when its ray to the outside boundary is unblocked!',
                ),
                const SizedBox(height: 10),

                // 2. 3 In-Level Shields
                _buildCard(
                  iconBg: const Color(0xFFFFE0E0),
                  icon: Icons.shield_rounded,
                  iconColor: const Color(0xFFE74C3C),
                  title: '3 In-Level Shields',
                  description:
                      'Tapping a blocked arrow triggers a collision and uses 1 shield. Clear the board before running out of shields!',
                ),
                const SizedBox(height: 10),

                // 3. Universal Hearts
                _buildCard(
                  iconBg: const Color(0xFFFFDEE6),
                  icon: Icons.favorite_rounded,
                  iconColor: const Color(0xFFFF4D79),
                  title: 'Universal Hearts ❤️',
                  description:
                      'You have 5 Max Hearts. If you fail or restart, 1 Heart is used. Hearts regenerate 1 every 10 minutes. Winning preserves your heart!',
                ),
                const SizedBox(height: 10),

                // 4. Coins & Rewards
                _buildCard(
                  iconBg: const Color(0xFFFFF0C7),
                  icon: Icons.star_rounded,
                  iconColor: const Color(0xFFF5A623),
                  title: 'Coins & Rewards 🪙',
                  description:
                      'Earn coins by completing levels. Use coins to instantly refill hearts or buy hints in the Shop!',
                ),

                const SizedBox(height: 18),

                // "GOT IT, LET'S PLAY!" Big Purple Button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9E54FF), Color(0xFF7020CA)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7020CA).withValues(alpha: 0.5),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          "GOT IT, LET'S PLAY!",
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Top Ribbon Header overlapping the card
        const Positioned(
          top: 0,
          child: RibbonHeader(
            title: 'HOW TO PLAY',
            bannerWidth: 240,
            height: 44,
            fontSize: 18,
          ),
        ),
      ],
    ),
  ),
);
  }

  Widget _buildCard({
    required Color iconBg,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEBE0CC),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF2C194D),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.nunito(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B5885),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
