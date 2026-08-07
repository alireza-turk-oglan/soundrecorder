import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/recorder_controller.dart';
import '../services/export_service.dart';
import '../widgets/channel_strip.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AudioFormat _format = AudioFormat.mp3;
  int _bitrate = 320;
  bool _exporting = false;
  String? _lastExportedPath;
  Timer? _lastExportTimer;

  @override
  void dispose() {
    _lastExportTimer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecorderController>();

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E13),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF00E5C3)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'ضبط صدای سیستم و میکروفن',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ChannelStrip(
                      title: 'میکروفن',
                      icon: Icons.mic_rounded,
                      volume: rec.micVolume,
                      muted: rec.micMuted,
                      level: rec.micLevel,
                      accentColor: const Color(0xFF7C4DFF),
                      onVolumeChanged: rec.setMicVolume,
                      onMuteToggle: rec.toggleMicMuted,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: ChannelStrip(
                      title: 'صدای ویندوز (سیستم)',
                      icon: Icons.speaker_rounded,
                      volume: rec.sysVolume,
                      muted: rec.sysMuted,
                      level: rec.sysLevel,
                      accentColor: const Color(0xFF00E5C3),
                      onVolumeChanged: rec.setSysVolume,
                      onMuteToggle: rec.toggleSysMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              _buildSaveLocationBar(rec),
              const SizedBox(height: 14),
              _buildFormatBar(),
              const Spacer(),
              _buildTransportControls(rec),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                reverseDuration: const Duration(milliseconds: 900),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
                    child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child),
                  ),
                ),
                child: _lastExportedPath != null ? _buildLastExport(key: ValueKey(_lastExportedPath)) : const SizedBox.shrink(key: ValueKey('empty')),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveLocationBar(RecorderController rec) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.folder_rounded, size: 18, color: Colors.white54),
          const SizedBox(width: 10),
          const Text('پوشه پیشنهادی برای ذخیره : ', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: FutureBuilder<String>(
              future: rec.resolveOutputDir(),
              builder: (context, snapshot) {
                final path = snapshot.data ?? '...';
                return Text(
                  path,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: rec.state == RecState.idle
                  ? () async {
                      try {
                        await rec.pickOutputDirectory();
                      } catch (e) {
                        _showError(e.toString());
                      }
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: rec.state == RecState.idle ? 0.15 : 0.05),
                  border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: rec.state == RecState.idle ? 0.5 : 0.15)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'تغییر مسیر',
                  style: TextStyle(
                    color: const Color(0xFF7C4DFF).withValues(alpha: rec.state == RecState.idle ? 1 : 0.4),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, size: 18, color: Colors.white54),
          const SizedBox(width: 10),
          const Text('فرمت خروجی : ', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 12),
          DropdownButton<AudioFormat>(
            value: _format,
            dropdownColor: const Color(0xFF1B1B22),
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(12),
            alignment: Alignment.center,
            icon: const Icon(Icons.expand_more_rounded, color: Colors.white54, size: 18),
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3),
            selectedItemBuilder: (context) => AudioFormat.values
                .map(
                  (f) => Align(
                    alignment: Alignment.center,
                    child: Text(
                      f.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                    ),
                  ),
                )
                .toList(),
            items: AudioFormat.values
                .map(
                  (f) => DropdownMenuItem(
                    value: f,
                    alignment: Alignment.center,
                    child: Text(
                      f.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _format = v!),
          ),
          const Spacer(),
          if (_format == AudioFormat.mp3 || _format == AudioFormat.aacM4a || _format == AudioFormat.ogg) ...[
            const Text('کیفیت (kbps) : ', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _bitrate,
              dropdownColor: const Color(0xFF1B1B22),
              underline: const SizedBox(),
              borderRadius: BorderRadius.circular(12),
              alignment: Alignment.center,
              icon: const Icon(Icons.expand_more_rounded, color: Colors.white54, size: 18),
              style: const TextStyle(color: Color(0xFF00E5C3), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3),
              selectedItemBuilder: (context) => const [128, 192, 256, 320]
                  .map(
                    (b) => Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 44,
                        child: Text(
                          '$b',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF00E5C3), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              items: const [128, 192, 256, 320]
                  .map(
                    (b) => DropdownMenuItem(
                      value: b,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 44,
                        child: Text(
                          '$b',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _bitrate = v!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransportControls(RecorderController rec) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (rec.state == RecState.idle)
              _bigButton(
                icon: Icons.fiber_manual_record_rounded,
                label: 'شروع ضبط',
                color: Colors.redAccent,
                onTap: () async {
                  try {
                    await rec.start();
                  } catch (e) {
                    _showError(e.toString());
                  }
                },
              )
            else ...[
              _bigButton(
                icon: rec.state == RecState.recording ? Icons.pause_rounded : Icons.play_arrow_rounded,
                label: rec.state == RecState.recording ? 'مکث' : 'ادامه',
                color: const Color(0xFF7C4DFF),
                onTap: () => rec.state == RecState.recording ? rec.pause() : rec.resume(),
              ),
              const SizedBox(width: 20),
              _buildTimerBadge(rec),
              const SizedBox(width: 20),
              _bigButton(
                icon: Icons.stop_rounded,
                label: 'توقف و ذخیره',
                color: const Color(0xFF00E5C3),
                onTap: () async {
                  final wavPath = await rec.stop();
                  if (wavPath == null) return;
                  setState(() => _exporting = true);
                  try {
                    final outPath = await rec.saveRecordingAs(_format, bitrateKbps: _bitrate);
                    setState(() => _exporting = false);
                    if (outPath == null) {
                      return;
                    }
                    setState(() => _lastExportedPath = outPath);
                    _lastExportTimer?.cancel();
                    _lastExportTimer = Timer(const Duration(seconds: 5), () {
                      if (!mounted) return;
                      setState(() => _lastExportedPath = null);
                    });
                  } catch (e) {
                    setState(() => _exporting = false);
                    _showError(e.toString());
                  }
                },
              ),
            ],
          ],
        ),
        if (_exporting)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
                SizedBox(width: 10),
                Text('در حال ذخیره‌سازی...', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTimerBadge(RecorderController rec) {
    final recording = rec.state == RecState.recording;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recording)
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            )
          else
            Icon(Icons.pause_circle_outline_rounded, size: 14, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 10),
          Text(
            _fmt(rec.elapsed),
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _buildLastExport({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5C3), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ذخیره شد : $_lastExportedPath',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _smallActionButton(icon: Icons.play_circle_outline_rounded, tooltip: 'باز کردن فایل', onTap: () => _openFile(_lastExportedPath!)),
            const SizedBox(width: 6),
            _smallActionButton(icon: Icons.folder_open_rounded, tooltip: 'باز کردن پوشه', onTap: () => _openContainingFolder(_lastExportedPath!)),
          ],
        ),
      ),
    );
  }

  Widget _smallActionButton({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: const Color(0xFF00E5C3)),
          ),
        ),
      ),
    );
  }

  Future<void> _openFile(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [path]);
      } else {
        _showError('این قابلیت فقط در ویندوز پشتیبانی می‌شود');
      }
    } catch (_) {
      _showError('امکان باز کردن فایل وجود ندارد');
    }
  }

  Future<void> _openContainingFolder(String path) async {
    try {
      if (Platform.isWindows) {
        final file = File(path);

        if (!await file.exists()) {
          _showError('فایل پیدا نشد');
          return;
        }

        final directory = file.parent.path;

        await Process.run('explorer.exe', [directory]);
      } else {
        _showError('این قابلیت فقط در ویندوز پشتیبانی می‌شود');
      }
    } catch (e) {
      _showError('امکان باز کردن پوشه وجود ندارد: $e');
    }
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        children: [
          _socialIcon(icon: FontAwesomeIcons.telegram, color: const Color(0xFF29A9EA), url: 'https://t.me/AlirezaHosseinzade'),
          const SizedBox(width: 16),
          _socialIcon(icon: FontAwesomeIcons.instagram, color: const Color(0xFFE1306C), url: 'https://www.instagram.com/alirezahosseinzadeh__'),
          const SizedBox(width: 16),
          _socialIcon(icon: FontAwesomeIcons.github, color: Colors.white70, url: 'https://github.com/alireza-turk-oglan'),
          const Spacer(),
          const Text(
            'Dev : Alireza Hosseinzadeh',
            style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _socialIcon({required FaIconData icon, required Color color, required String url}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openLink(url),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: FaIcon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _showError('امکان باز کردن لینک وجود ندارد');
    } catch (e) {
      _showError('امکان باز کردن لینک وجود ندارد');
    }
  }

  Widget _bigButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent, duration: const Duration(seconds: 5)));
  }
}
