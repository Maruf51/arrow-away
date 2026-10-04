import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_colors.dart';
import '../../core/constants.dart';
import '../../data/repositories/progress_repository.dart';
import '../../core/audio_manager.dart';

class LevelSelectScreen extends StatelessWidget {
  const LevelSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressRepository>();
    const totalVisible = 500;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ─────────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        AudioManager.instance.playClick();
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: AppColors.purpleGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.purple.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'ALL LEVELS',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.gold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Grid ───────────────────────────────────────────────────────
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: totalVisible,
                  itemBuilder: (context, index) {
                    final levelNum = index + 1;
                    final isUnlocked = progress.isLevelUnlocked(levelNum);
                    final stars = progress.getStarsForLevel(levelNum);
                    final levelType = AppConstants.levelTypeFor(levelNum);

                    return _LevelCell(
                      levelNumber: levelNum,
                      isUnlocked: isUnlocked,
                      stars: stars,
                      levelType: levelType,
                      onTap: isUnlocked
                          ? () {
                              AudioManager.instance.playClick();
                              Navigator.pushReplacementNamed(
                                context,
                                '/game',
                                arguments: {'level': levelNum},
                              );
                            }
                          : null,
                    )
                        .animate(
                            delay:
                                Duration(milliseconds: (index % 20) * 20))
                        .fadeIn(duration: 200.ms)
                        .scale(
                            begin: const Offset(0.7, 0.7),
                            end: const Offset(1, 1));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelCell extends StatelessWidget {
  final int levelNumber;
  final bool isUnlocked;
  final int stars;
  final LevelType levelType;
  final VoidCallback? onTap;

  const _LevelCell({
    required this.levelNumber,
    required this.isUnlocked,
    required this.stars,
    required this.levelType,
    required this.onTap,
  });

  Color get _borderColor {
    if (!isUnlocked) return AppColors.purpleDark;
    switch (levelType) {
      case LevelType.god:
        return const Color(0xFFE74C3C);
      case LevelType.boss:
        return AppColors.purpleLight;
      case LevelType.tutorial:
        return AppColors.green;
      case LevelType.normal:
        return AppColors.purple.withValues(alpha: 0.5);
    }
  }

  LinearGradient get _cellGradient {
    if (!isUnlocked) {
      return const LinearGradient(
        colors: [Color(0xFF1A0F3C), Color(0xFF200E40)],
      );
    }
    switch (levelType) {
      case LevelType.god:
        return const LinearGradient(
          colors: [Color(0xFF6B1010), Color(0xFF4A0A0A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case LevelType.boss:
        return AppColors.purpleGradient;
      default:
        return const LinearGradient(
          colors: [Color(0xFF3A1D80), Color(0xFF2A1260)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: _cellGradient,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor, width: 1.5),
          boxShadow: isUnlocked && levelType.isSpecial
              ? [
                  BoxShadow(
                    color: _borderColor.withValues(alpha: 0.4),
                    blurRadius: 10,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Level type badge icon
            if (levelType == LevelType.god)
              const Icon(LucideIcons.flame, color: Color(0xFFE74C3C), size: 12)
            else if (levelType == LevelType.boss)
              Icon(LucideIcons.zap, color: AppColors.purpleLight, size: 12)
            else if (levelType == LevelType.tutorial)
              Icon(LucideIcons.bookOpen, color: AppColors.green, size: 12),

            if (!isUnlocked)
              const Icon(Icons.lock_outline_rounded,
                  color: Color(0xFF6B5B9A), size: 20)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$levelNumber',
                    style: GoogleFonts.nunito(
                      fontSize: levelNumber >= 100 ? 13 : 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // Stars
            if (isUnlocked && stars > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => Icon(
                    i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 9,
                    color: i < stars
                        ? AppColors.gold
                        : AppColors.purpleLight.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
