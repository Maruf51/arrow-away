import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../ads/ad_manager.dart';
import '../../core/app_colors.dart';
import '../../core/audio_manager.dart';
import '../../core/constants.dart';
import '../../data/repositories/progress_repository.dart';

class DailyChallengeScreen extends StatefulWidget {
  const DailyChallengeScreen({super.key});

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen> {
  final DateTime _today = DateTime.now();
  Map<int, int>? _assignments;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final progress = context.read<ProgressRepository>();
      await progress.refreshHearts();
      final assignments = await progress.ensureDailyChallengesForMonth(_today);
      if (mounted) setState(() => _assignments = assignments);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressRepository>();
    final monthName = _monthName(_today.month);
    final firstWeekday = DateTime(_today.year, _today.month, 1).weekday % 7;
    final dayCount = DateTime(_today.year, _today.month + 1, 0).day;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'DAILY CHALLENGE',
                      style: GoogleFonts.nunito(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surfaceLight),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.local_fire_department_rounded,
                          color: Color(0xFFFF8A45), size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${progress.dailyChallengeStreak} DAY STREAK',
                              style: GoogleFonts.nunito(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              'Consecutive completed days in $monthName',
                              style: GoogleFonts.nunito(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$monthName ${_today.year}',
                        textAlign: TextAlign.end,
                        style: GoogleFonts.nunito(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildStreakRewardCard(context, progress),
                const SizedBox(height: 14),
                Row(
                  children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                      .map((day) => Expanded(
                            child: Center(
                              child: Text(
                                day,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _assignments == null
                      ? const Center(child: CircularProgressIndicator())
                      : GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 7,
                            crossAxisSpacing: 7,
                          ),
                          itemCount: firstWeekday + dayCount,
                          itemBuilder: (context, index) {
                            if (index < firstWeekday) return const SizedBox();
                            final day = index - firstWeekday + 1;
                            final date = DateTime(_today.year, _today.month, day);
                            final dateKey = ProgressRepository.dailyChallengeDateKey(date);
                            final stars = progress.dailyChallengeStars(dateKey);
                            final isToday = day == _today.day;
                            final isFuture = date.isAfter(
                              DateTime(_today.year, _today.month, _today.day),
                            );
                            return _DailyDayCell(
                              day: day,
                              stars: stars,
                              isToday: isToday,
                              isFuture: isFuture,
                              onTap: isFuture ? null : () => _playChallenge(day, dateKey),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star_rounded, color: AppColors.gold, size: 17),
                    const SizedBox(width: 6),
                    Text(
                      'Completed',
                      style: GoogleFonts.nunito(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 22),
                    const Icon(Icons.circle, color: Color(0xFF65E6A1), size: 9),
                    const SizedBox(width: 6),
                    Text(
                      'Today',
                      style: GoogleFonts.nunito(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreakRewardCard(
    BuildContext context,
    ProgressRepository progress,
  ) {
    final reward = progress.currentStreakReward;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  color: Color(0xFFFF8A45), size: 23),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Day ${progress.currentStreakDayInCycle} of 7',
                  style: GoogleFonts.nunito(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!progress.hasUnclaimedStreakReward)
                Text(
                  'Claimed today ✓',
                  style: GoogleFonts.nunito(
                    color: AppColors.textSecondary.withValues(alpha: 0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              if (reward[0] > 0)
                _StreakRewardAmount(
                  icon: Icons.monetization_on_rounded,
                  color: AppColors.gold,
                  amount: reward[0],
                ),
              if (reward[1] > 0)
                _StreakRewardAmount(
                  icon: Icons.lightbulb_rounded,
                  color: const Color(0xFFFFD45E),
                  amount: reward[1],
                ),
              if (reward[2] > 0)
                _StreakRewardAmount(
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFFF5B78),
                  amount: reward[2],
                ),
            ],
          ),
          if (progress.hasUnclaimedStreakReward) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => _claimStreakReward(progress),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'CLAIM',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w900),
              ),
            ),
          ],
          if (progress.hasUnclaimedStreakAdBonus) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _claimStreakAdBonus(context, progress),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 19),
              label: Text(
                'Watch Ad for +${AppConstants.dailyStreakAdBonusCoins} 🪙 and +${AppConstants.dailyStreakAdBonusHints} 💡',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: AppColors.surfaceLight),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _claimStreakReward(ProgressRepository progress) {
    final reward = progress.claimStreakReward();
    if (reward.every((amount) => amount == 0)) return;
    _showRewardSnackbar(_formatStreakReward(reward));
  }

  Future<void> _claimStreakAdBonus(
    BuildContext context,
    ProgressRepository progress,
  ) async {
    final adManager = context.read<AdManager>();
    if (!adManager.isRewardedAvailable) {
      _showRewardSnackbar('Ad not available, try again later.');
      return;
    }

    var rewardClaimed = false;
    await adManager.showRewardedWithLoader(
      context,
      strictReward: true,
      onRewarded: () {
        rewardClaimed = true;
        final reward = progress.claimStreakAdBonus();
        if (reward[0] > 0 || reward[1] > 0) {
          _showRewardSnackbar(_formatStreakAdBonus(reward));
        }
      },
      onDismissed: () {
        if (!rewardClaimed && mounted) {
          _showRewardSnackbar('Ad not available, try again later.');
        }
      },
    );
  }

  String _formatStreakReward(List<int> reward) {
    final parts = <String>[];
    if (reward[0] > 0) parts.add('${reward[0]} coins');
    if (reward[1] > 0) parts.add('${reward[1]} ${reward[1] == 1 ? 'hint' : 'hints'}');
    if (reward[2] > 0) parts.add('${reward[2]} ${reward[2] == 1 ? 'heart' : 'hearts'}');
    return 'Claimed ${_joinRewardParts(parts)}!';
  }

  String _formatStreakAdBonus(List<int> reward) {
    final parts = <String>[];
    if (reward[0] > 0) parts.add('${reward[0]} coins');
    if (reward[1] > 0) parts.add('${reward[1]} ${reward[1] == 1 ? 'hint' : 'hints'}');
    return 'Claimed ${_joinRewardParts(parts)}!';
  }

  String _joinRewardParts(List<String> parts) {
    if (parts.length < 2) return parts.single;
    if (parts.length == 2) return '${parts[0]} and ${parts[1]}';
    return '${parts[0]}, ${parts[1]}, and ${parts[2]}';
  }

  void _showRewardSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _playChallenge(int day, String dateKey) async {
    final seed = _assignments?[day];
    if (seed == null) return;
    AudioManager.instance.playClick();
    await Navigator.pushNamed(
      context,
      '/game',
      arguments: {
        'level': 480,
        'dailyChallengeSeed': seed,
        'dailyChallengeDateKey': dateKey,
      },
    );
  }

  String _monthName(int month) => const [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][month - 1];
}

class _StreakRewardAmount extends StatelessWidget {
  const _StreakRewardAmount({
    required this.icon,
    required this.color,
    required this.amount,
  });

  final IconData icon;
  final Color color;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 4),
        Text(
          '$amount',
          style: GoogleFonts.nunito(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _DailyDayCell extends StatelessWidget {
  const _DailyDayCell({
    required this.day,
    required this.stars,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  final int day;
  final int? stars;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final completed = stars != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: completed
                ? AppColors.gold.withValues(alpha: 0.14)
                : AppColors.surface.withValues(alpha: isFuture ? 0.25 : 0.62),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday
                  ? const Color(0xFF65E6A1)
                  : completed
                      ? AppColors.gold.withValues(alpha: 0.75)
                      : AppColors.surfaceLight.withValues(alpha: 0.65),
              width: isToday ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: GoogleFonts.nunito(
                  color: isFuture ? AppColors.textSecondary.withValues(alpha: 0.5) : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (completed)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    stars!.clamp(1, 3),
                    (_) => const Icon(Icons.star_rounded,
                        color: AppColors.gold, size: 10),
                  ),
                )
              else if (isToday)
                const Icon(Icons.circle, color: Color(0xFF65E6A1), size: 7)
              else
                const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }
}