import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/audio_manager.dart';
import '../data/repositories/progress_repository.dart';
import 'ribbon_header.dart';

class ShopDialog extends StatefulWidget {
  final int initialTab; // 0: Skins, 1: Coins, 2: Hints & Lives

  const ShopDialog({
    super.key,
    this.initialTab = 0,
  });

  static Future<void> show(BuildContext context, {int initialTab = 0}) {
    return showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => ShopDialog(initialTab: initialTab),
    );
  }

  @override
  State<ShopDialog> createState() => _ShopDialogState();
}

class _ShopDialogState extends State<ShopDialog> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  String _formatNumber(int n) {
    if (n < 1000) return '$n';
    return n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressRepository>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                padding: const EdgeInsets.fromLTRB(16, 36, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Status Pill (Lives, Coins, Hints)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFEBE0CC),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Lives
                          Row(
                            children: [
                              const Text('❤️', style: TextStyle(fontSize: 13)),
                              const SizedBox(width: 4),
                              Text(
                                '${progress.lives}/${progress.maxLives}',
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF2C194D),
                                ),
                              ),
                            ],
                          ),
                          // Coins
                          Row(
                            children: [
                              const Text('🪙', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              Text(
                                _formatNumber(progress.coins),
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF2C194D),
                                ),
                              ),
                            ],
                          ),
                          // Hints
                          Row(
                            children: [
                              const Text('💡', style: TextStyle(fontSize: 13)),
                              const SizedBox(width: 4),
                              Text(
                                '${progress.hints} Hints',
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF2C194D),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (progress.hasUnclaimedDailyCoin) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDF8),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFEBE0CC),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.monetization_on_rounded,
                              color: Color(0xFFE5A91A),
                              size: 27,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Daily Free Coins',
                                style: GoogleFonts.nunito(
                                  color: const Color(0xFF2C194D),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF00A85A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 9),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                AudioManager.instance.playClick();
                                final claimed = progress.claimDailyCoin();
                                if (claimed > 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Claimed $claimed coins!'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              child: Text(
                                'CLAIM +${AppConstants.dailyFreeCoins} 🪙',
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 3 Tabs (SKINS, COINS, 💡 & ❤️)
                    Row(
                      children: [
                        _buildTab(0, '🏹 SKINS'),
                        const SizedBox(width: 6),
                        _buildTab(1, '🪙 COINS'),
                        const SizedBox(width: 6),
                        _buildTab(2, '💡 & ❤️'),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Content based on selected tab
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: _selectedTab == 0
                            ? _buildSkinsTab(context, progress)
                            : _selectedTab == 1
                                ? _buildCoinsTab(context, progress)
                                : _buildHintsLivesTab(context, progress),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Bottom CLOSE Button
                    GestureDetector(
                      onTap: () {
                        AudioManager.instance.playClick();
                        Navigator.pop(context);
                      },
                      child: Container(
                        height: 52,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF9E54FF), Color(0xFF7020CA)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7020CA)
                                  .withValues(alpha: 0.5),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'CLOSE',
                          style: GoogleFonts.nunito(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
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
                title: 'SHOP',
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

  Widget _buildTab(int index, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          AudioManager.instance.playClick();
          setState(() => _selectedTab = index);
        },
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF8F46E8), Color(0xFF6C28C7)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : null,
            color: isSelected ? null : const Color(0xFFFFFDF8),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: isSelected ? Colors.transparent : const Color(0xFFEBE0CC),
              width: 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF6C28C7).withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isSelected ? Colors.white : const Color(0xFF2C194D),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkinsTab(BuildContext context, ProgressRepository progress) {
    final currentSkin = progress.equippedSkin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CUSTOMIZE ARROW SKINS & TRAILS',
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF2C194D),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),

        // 1. Classic (Default White)
        _buildSkinCard(
          title: 'Classic',
          isActive: currentSkin == 'classic',
          trailText: 'Trail: Smooth Streak',
          trailColor: const Color(0xFF8F46E8),
          description: 'Clean, iconic rounded arrows with crisp chevron heads.',
          iconWidget: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF3E8FF),
              border: Border.all(color: const Color(0xFFD8B4FE), width: 1.5),
            ),
            child: const Center(
              child: Icon(
                Icons.adjust_rounded,
                color: Color(0xFF8F46E8),
                size: 26,
              ),
            ),
          ),
          onEquipTap: currentSkin == 'classic'
              ? null
              : () {
                  AudioManager.instance.playClick();
                  progress.setEquippedSkin('classic');
                },
        ),

        const SizedBox(height: 12),

        // 2. Rainbow (Random / Rainbow Colored)
        _buildSkinCard(
          title: 'Rainbow',
          isActive: currentSkin == 'rainbow',
          trailText: 'Trail: Color Spectrum',
          trailColor: const Color(0xFF00BFA5),
          description:
              'Vibrant spectrum of rainbow colors illuminating every arrow on the board.',
          iconWidget: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(
                colors: [
                  Color(0xFFFF334B),
                  Color(0xFFFF7A00),
                  Color(0xFFFFD000),
                  Color(0xFF00E676),
                  Color(0xFF00E5FF),
                  Color(0xFF2979FF),
                  Color(0xFFA855F7),
                  Color(0xFFFF2A8D),
                  Color(0xFFFF334B),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: const Center(
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFFF9500),
                  size: 22,
                ),
              ),
            ),
          ),
          onEquipTap: currentSkin == 'rainbow'
              ? null
              : () {
                  AudioManager.instance.playClick();
                  progress.setEquippedSkin('rainbow');
                },
        ),

        const SizedBox(height: 12),

        // 3. Neon Flow (Red liquid tube)
        _buildSkinCard(
          title: 'Neon Flow',
          isActive: currentSkin == 'liquid_neon',
          trailText: 'Trail: Liquid Halo',
          trailColor: const Color(0xFFFF1744),
          description:
              'Red neon arrows with slow white liquid flowing from tail to head.',
          iconWidget: const _LiquidNeonSkinIcon(),
          onEquipTap: currentSkin == 'liquid_neon'
              ? null
              : () {
                  AudioManager.instance.playClick();
                  progress.setEquippedSkin('liquid_neon');
                },
        ),
      ],
    );
  }

  Widget _buildSkinCard({
    required String title,
    required bool isActive,
    required String trailText,
    required Color trailColor,
    required String description,
    required Widget iconWidget,
    required VoidCallback? onEquipTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? const Color(0xFF00BFA5) : const Color(0xFFEBE0CC),
          width: isActive ? 2.0 : 1.5,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF00BFA5).withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon on left
          iconWidget,
          const SizedBox(width: 12),

          // Info in middle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF2C194D),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C853),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'ACTIVE',
                          style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  trailText,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: trailColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B5885),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Action button on right
          GestureDetector(
            onTap: onEquipTap,
            child: Container(
              width: 88,
              height: 48,
              decoration: BoxDecoration(
                gradient: onEquipTap == null
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF8F46E8), Color(0xFF6C28C7)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                color: onEquipTap == null ? const Color(0xFF828A94) : null,
                borderRadius: BorderRadius.circular(14),
                boxShadow: onEquipTap == null
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFF6C28C7).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              alignment: Alignment.center,
              child: Text(
                onEquipTap == null ? 'EQUIPPED' : 'EQUIP',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoinsTab(BuildContext context, ProgressRepository progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COINS ARE EARNED BY CLEARING LEVELS',
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF2C194D),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildHintsLivesTab(
      BuildContext context, ProgressRepository progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REFILL LIVES & GET HINTS',
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF2C194D),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        // Full Lives
        _buildStoreItemCard(
          icon: '❤️',
          title: 'Full Lives Refill',
          subtitle: 'Restore 5 maximum hearts',
          buttonText: '${AppConstants.heartCostFullRefill} 🪙',
          buttonColor: const Color(0xFFFF4D79),
            onTap: progress.coins >= AppConstants.heartCostFullRefill &&
              !progress.livesAreFull
              ? () async {
                  AudioManager.instance.playClick();
                  final purchased = await progress.purchaseHearts(
                    amount: AppConstants.maxLives,
                    cost: AppConstants.heartCostFullRefill,
                  );
                  if (!purchased || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Lives fully restored! ❤️',
                        style: GoogleFonts.nunito(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: const Color(0xFFFF4D79),
                    ),
                  );
                }
              : () {
                  if (progress.livesAreFull) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Your hearts are already full.')),
                    );
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Need ${AppConstants.heartCostFullRefill} coins! Play levels or get coins.',
                        style: GoogleFonts.nunito(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: const Color(0xFFE74C3C),
                    ),
                  );
                },
        ),
        const SizedBox(height: 10),
        // +3 Hints
        _buildStoreItemCard(
          icon: '💡',
          title: '+3 Puzzle Hints',
          subtitle: 'Show safe clearable arrows',
          buttonText: '${AppConstants.hintCostPack3} 🪙',
          buttonColor: const Color(0xFF8F46E8),
          onTap: progress.coins >= AppConstants.hintCostPack3
              ? () {
                  AudioManager.instance.playClick();
                  progress.addCoins(-AppConstants.hintCostPack3);
                  progress.addHints(3);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '+3 Hints added! 💡',
                        style: GoogleFonts.nunito(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: const Color(0xFF8F46E8),
                    ),
                  );
                }
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Need ${AppConstants.hintCostPack3} coins! Play levels or get coins.',
                        style: GoogleFonts.nunito(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: const Color(0xFFE74C3C),
                    ),
                  );
                },
        ),
      ],
    );
  }

  Widget _buildStoreItemCard({
    required String icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required Color buttonColor,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFEBE0CC),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
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
                Text(
                  subtitle,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B5885),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: buttonColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: buttonColor.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                buttonText,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiquidNeonSkinIcon extends StatelessWidget {
  const _LiquidNeonSkinIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2A0610),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF1744).withValues(alpha: 0.35),
            blurRadius: 10,
          ),
        ],
      ),
      child: const CustomPaint(
        painter: _LiquidNeonSkinIconPainter(),
      ),
    );
  }
}

class _LiquidNeonSkinIconPainter extends CustomPainter {
  const _LiquidNeonSkinIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final start = Offset(size.width * 0.20, centerY);
    final end = Offset(size.width * 0.76, centerY);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF1744).withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF1638)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF8F001B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    final head = Path()
      ..moveTo(size.width * 0.80, centerY)
      ..lineTo(size.width * 0.58, size.height * 0.30)
      ..lineTo(size.width * 0.58, size.height * 0.70)
      ..close();
    canvas.drawPath(
      head,
      Paint()
        ..color = const Color(0xFFFF1638)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      head,
      Paint()
        ..color = const Color(0xFF650013)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawLine(
      Offset(size.width * 0.29, centerY),
      Offset(size.width * 0.55, centerY),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
