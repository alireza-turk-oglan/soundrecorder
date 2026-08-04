import 'package:flutter/material.dart';

class ChannelStrip extends StatelessWidget {
  final String title;
  final IconData icon;
  final double volume;
  final bool muted;
  final double level; // 0.0 - 1.0
  final Color accentColor;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMuteToggle;

  const ChannelStrip({
    super.key,
    required this.title,
    required this.icon,
    required this.volume,
    required this.muted,
    required this.level,
    required this.accentColor,
    required this.onVolumeChanged,
    required this.onMuteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: muted ? Colors.grey : accentColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: muted ? Colors.grey : Colors.white,
                  ),
                ),
              ),
              _MuteButton(
                muted: muted,
                onTap: onMuteToggle,
                color: accentColor,
                baseIcon: icon,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // متر سطح صدا
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(color: Colors.white.withValues(alpha: 0.06)),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        width:
                            constraints.maxWidth *
                            (muted ? 0 : level.clamp(0, 1)),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor.withValues(alpha: 0.6),
                              accentColor,
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Icon(
                  Icons.volume_down,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: accentColor,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                      thumbColor: accentColor,
                      overlayColor: accentColor.withValues(alpha: 0.2),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: Slider(
                      value: volume.clamp(0.0, 2.0),
                      min: 0.0,
                      max: 2.0,
                      onChanged: muted ? null : onVolumeChanged,
                    ),
                  ),
                ),
                Icon(
                  Icons.volume_up,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(volume * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.end,
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

class _MuteButton extends StatelessWidget {
  final bool muted;
  final Color color;
  final IconData baseIcon;
  final VoidCallback onTap;

  const _MuteButton({
    required this.muted,
    required this.onTap,
    required this.color,
    required this.baseIcon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: muted
              ? Colors.redAccent.withValues(alpha: 0.15)
              : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(baseIcon, size: 18, color: muted ? Colors.redAccent : color),
            if (muted)
              Transform.rotate(
                angle: -0.78,
                child: Container(width: 2, height: 20, color: Colors.redAccent),
              ),
          ],
        ),
      ),
    );
  }
}
