import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/repositories/progress_repository.dart';
import '../../core/audio_manager.dart';
import '../../widgets/ribbon_header.dart';
import '../main_menu/main_menu_screen.dart' show HowToPlayDialog;

/// Settings modal dialog, matching the purple/gold ribbon game design.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

/// Backwards compatibility alias so any existing route or import still works
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(child: SettingsDialog()),
    );
  }
}

class _SettingsDialogState extends State<SettingsDialog> {
  static const String _privacyPolicyUrl =
      'https://gxdevs.blogspot.com/2026/07/arrow-escape-privacy-policy.html';

  bool _gridDots = true;
  bool _startArrowAnimation = true;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressRepository>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // ── Cream Card Body ─────────────────────────────────────────
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
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1. Sound Effects
                            _SettingToggleCard(
                              label: 'Sound Effects',
                              value: progress.soundEnabled,
                              onChanged: (val) {
                                AudioManager.instance.playClick();
                                progress.setSoundEnabled(val);
                              },
                            ),
                            const SizedBox(height: 10),

                            // 2. Haptic Feedback
                            _SettingToggleCard(
                              label: 'Haptic Feedback',
                              value: progress.vibrationEnabled,
                              onChanged: (val) {
                                AudioManager.instance.playClick();
                                progress.setVibrationEnabled(val);
                              },
                            ),
                            const SizedBox(height: 10),

                            // 3. Grid Background Dots
                            _SettingToggleCard(
                              label: 'Grid Background Dots',
                              value: _gridDots,
                              onChanged: (val) {
                                AudioManager.instance.playClick();
                                setState(() => _gridDots = val);
                              },
                            ),
                            const SizedBox(height: 10),

                            // 4. Start Arrow Animation
                            _SettingToggleCard(
                              label: 'Start Arrow Animation',
                              value: _startArrowAnimation,
                              onChanged: (val) {
                                AudioManager.instance.playClick();
                                setState(() => _startArrowAnimation = val);
                              },
                            ),
                            const SizedBox(height: 10),

                            // 5. Show Framerate (FPS)
                            _SettingToggleCard(
                              label: 'Show Framerate (FPS)',
                              value: progress.showFps,
                              onChanged: (val) {
                                AudioManager.instance.playClick();
                                progress.setShowFps(val);
                              },
                            ),
                            const SizedBox(height: 10),

                            // 6. Arrow Exit Speed Section
                            _buildArrowExitSpeedCard(progress),
                            const SizedBox(height: 10),

                            // 7. How to Play Button
                            _buildActionCard(
                              icon: Icons.help_outline_rounded,
                              label: 'How to Play',
                              onTap: () {
                                AudioManager.instance.playClick();
                                showDialog(
                                  context: context,
                                  barrierColor: Colors.black87,
                                  builder: (_) => const HowToPlayDialog(),
                                );
                              },
                            ),
                            const SizedBox(height: 10),

                            // 8. Terms & Privacy Policy Button
                            _buildActionCard(
                              icon: Icons.shield_outlined,
                              label: 'Terms & Privacy Policy',
                              onTap: () {
                                AudioManager.instance.playClick();
                                _launchUrl(_privacyPolicyUrl);
                              },
                            ),
                            const SizedBox(height: 10),

                            // 9. Reset Progress Button
                            _buildResetProgressCard(context, progress),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Bottom CLOSE Button (Full Width Purple Pill)
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
                              color: const Color(0xFF7020CA).withValues(alpha: 0.45),
                              blurRadius: 10,
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

            // ── Top Ribbon Header ───────────────────────────────────────
            const Positioned(
              top: 0,
              child: RibbonHeader(
                title: 'SETTINGS',
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

  Widget _buildArrowExitSpeedCard(ProgressRepository progress) {
    const speeds = ['Slow', 'Normal', 'Fast'];
    final selectedIndex = progress.arrowSpeedIndex.clamp(0, 2);
    final currentLabel = speeds[selectedIndex];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEBE0CC),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Arrow Exit Speed',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF2C194D),
                ),
              ),
              Text(
                currentLabel,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF7E38E6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(speeds.length, (i) {
              final isSelected = i == selectedIndex;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : 4,
                    right: i == speeds.length - 1 ? 0 : 4,
                  ),
                  child: GestureDetector(
                    onTap: () {
                      AudioManager.instance.playClick();
                      progress.setArrowSpeedIndex(i);
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
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : const Color(0xFFEBE0CC),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        speeds[i],
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF2C194D),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
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
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFFE8D7FF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF7E38E6), size: 18),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF2C194D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResetProgressCard(BuildContext context, ProgressRepository progress) {
    return GestureDetector(
      onTap: () {
        AudioManager.instance.playClick();
        _showResetConfirm(context, progress);
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7F7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFFFD4D4),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          'Reset Progress',
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFE74C3C),
          ),
        ),
      ),
    );
  }

  void _showResetConfirm(BuildContext context, ProgressRepository progress) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFFFF9EE),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Reset Progress?',
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF2C194D),
          ),
        ),
        content: Text(
          'This will reset your levels and score back to level 1. Are you sure?',
          style: GoogleFonts.nunito(
            color: const Color(0xFF6B5885),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF7E38E6),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              progress.setCurrentLevel(1);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Progress reset to Level 1',
                    style: GoogleFonts.nunito(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: const Color(0xFFE74C3C),
                ),
              );
            },
            child: Text(
              'Reset',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w800,
                color: const Color(0xFFE74C3C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Setting Toggle Card with Purple Switch ───────────────────────────────────
class _SettingToggleCard extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingToggleCard({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEBE0CC),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2C194D),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF7E38E6),
            activeThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFE8E0F0),
            inactiveThumbColor: Colors.white,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ],
      ),
    );
  }
}

