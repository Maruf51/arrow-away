import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ResourceOfferAction {
  const ResourceOfferAction({
    required this.label,
    required this.value,
    required this.price,
    required this.icon,
    required this.color,
    this.enabled = true,
  });

  final String label;
  final String value;
  final String price;
  final IconData icon;
  final Color color;
  final bool enabled;
}

class ResourceOfferDialog extends StatelessWidget {
  const ResourceOfferDialog({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.actions,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final List<ResourceOfferAction> actions;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
    required List<ResourceOfferAction> actions,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => ResourceOfferDialog(
        title: title,
        message: message,
        icon: icon,
        iconColor: iconColor,
        actions: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 42, 20, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9EE),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFEBE0CC), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        color: const Color(0xFF2C194D),
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        color: const Color(0xFF6B5885),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final action in actions) ...[
                      SizedBox(
                        width: double.infinity,
                        child: _OfferButton(
                          action: action,
                          onTap: action.enabled
                              ? () => Navigator.pop(context, action.value)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 9),
                    ],
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'NOT NOW',
                        style: GoogleFonts.nunito(
                          color: const Color(0xFF6B5885),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor,
                border: Border.all(color: const Color(0xFFFFF9EE), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 29),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferButton extends StatelessWidget {
  const _OfferButton({required this.action, required this.onTap});

  final ResourceOfferAction action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = action.enabled ? action.color : const Color(0xFFB9AFBD);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            boxShadow: action.enabled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 7,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(action.icon, color: Colors.white, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.label,
                  style: GoogleFonts.nunito(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                action.price,
                style: GoogleFonts.nunito(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
