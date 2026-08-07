import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../services/recorder_controller.dart';

enum _SortMode { dateNewest, dateOldest, nameAsc, nameDesc }

extension _SortModeX on _SortMode {
  String get label {
    switch (this) {
      case _SortMode.dateNewest:
        return 'جدیدترین';
      case _SortMode.dateOldest:
        return 'قدیمی‌ترین';
      case _SortMode.nameAsc:
        return 'نام (الف تا ی)';
      case _SortMode.nameDesc:
        return 'نام (ی تا الف)';
    }
  }

  IconData get icon {
    switch (this) {
      case _SortMode.dateNewest:
      case _SortMode.dateOldest:
        return Icons.schedule_rounded;
      case _SortMode.nameAsc:
      case _SortMode.nameDesc:
        return Icons.sort_by_alpha_rounded;
    }
  }

  _SortMode get next {
    switch (this) {
      case _SortMode.dateNewest:
        return _SortMode.dateOldest;
      case _SortMode.dateOldest:
        return _SortMode.nameAsc;
      case _SortMode.nameAsc:
        return _SortMode.nameDesc;
      case _SortMode.nameDesc:
        return _SortMode.dateNewest;
    }
  }
}

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => RecordingsScreenState();
}

class RecordingsScreenState extends State<RecordingsScreen> {
  static const _audioExtensions = {'.wav', '.mp3', '.m4a', '.flac', '.ogg'};

  List<File> _files = [];
  bool _loading = true;
  String? _error;
  String? _dirPath;
  String? _tempPath;
  _SortMode _sortMode = _SortMode.dateNewest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rec = context.read<RecorderController>();
      final dirPath = await rec.resolveOutputDir();
      final tempBase = await getTemporaryDirectory();
      final tempPath = p.join(tempBase.path, 'WinAudioRecorderTemp');
      final dir = Directory(dirPath);

      final files = <File>[];
      if (await dir.exists()) {
        for (final entity in dir.listSync()) {
          if (entity is File && _audioExtensions.contains(p.extension(entity.path).toLowerCase())) {
            files.add(entity);
          }
        }
        _sortFiles(files);
      }

      if (!mounted) return;
      setState(() {
        _dirPath = dirPath;
        _tempPath = tempPath;
        _files = files;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'خطا در خواندن لیست فایل‌ها : $e';
        _loading = false;
      });
    }
  }

  void _sortFiles(List<File> files) {
    switch (_sortMode) {
      case _SortMode.dateNewest:
        files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        break;
      case _SortMode.dateOldest:
        files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
        break;
      case _SortMode.nameAsc:
        files.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
        break;
      case _SortMode.nameDesc:
        files.sort((a, b) => p.basename(b.path).toLowerCase().compareTo(p.basename(a.path).toLowerCase()));
        break;
    }
  }

  void _cycleSortMode() {
    setState(() {
      _sortMode = _sortMode.next;
      _sortFiles(_files);
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final jalali = Jalali.fromDateTime(dt);
    return '${jalali.year}/${two(jalali.month)}/${two(jalali.day)} - ${two(dt.hour)}:${two(dt.minute)}';
  }

  IconData _iconFor(String ext) {
    switch (ext) {
      case '.wav':
        return Icons.graphic_eq_rounded;
      case '.flac':
        return Icons.high_quality_rounded;
      case '.ogg':
        return Icons.audiotrack_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }

  Future<void> _openFile(String path) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('explorer.exe', [path]);
        if (result.pid == 0) {
          _showError('امکان باز کردن فایل وجود ندارد');
        }
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
  }

  Future<void> _deleteFile(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف فایل', style: TextStyle(color: Colors.white)),
        content: Text('آیا از حذف «${p.basename(file.path)}» مطمئن هستید؟ این عملیات قابل بازگشت نیست.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await file.delete();
      if (!mounted) return;
      setState(() {
        _files.removeWhere((f) => f.path == file.path);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فایل حذف شد'), backgroundColor: Color(0xFF00E5C3)));
    } catch (e) {
      _showError('امکان حذف فایل وجود ندارد : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E13),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF00E5C3)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.folder_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'فایل‌های ضبط شده',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    child: Tooltip(
                      message: 'مرتب‌سازی : ${_sortMode.label} (برای تغییر ضربه بزنید)',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _cycleSortMode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
                            border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_sortMode.icon, size: 16, color: const Color(0xFF7C4DFF)),
                              const SizedBox(width: 8),
                              Text(
                                _sortMode.label,
                                style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: refresh,
                    tooltip: 'بروزرسانی لیست',
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
                  ),
                ],
              ),
              if (_dirPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 18),
                  child: Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      const Icon(Icons.place_outlined, size: 14, color: Colors.white38),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Temp : ${_tempPath ?? ''}",
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.left,
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Saved : ${_dirPath!}",
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.left,
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 22),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7C4DFF)));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      );
    }
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 14),
            const Text('هنوز فایلی ضبط نشده است', style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      color: const Color(0xFF7C4DFF),
      backgroundColor: const Color(0xFF1B1B22),
      child: ListView.separated(
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final file = _files[index];
          final name = p.basename(file.path);
          final ext = p.extension(file.path).toLowerCase();
          final stat = file.statSync();

          return Material(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openFile(file.path),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    IconButton(
                      onPressed: () => _openContainingFolder(file.path),
                      tooltip: 'باز کردن پوشه',
                      icon: const Icon(Icons.folder_open_rounded, color: Colors.white54, size: 20),
                    ),
                    IconButton(
                      onPressed: () => _openFile(file.path),
                      tooltip: 'پخش با پلیر پیش‌فرض ویندوز',
                      icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF00E5C3), size: 22),
                    ),
                    IconButton(
                      onPressed: () => _deleteFile(file),
                      tooltip: 'حذف فایل',
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text('${_formatDate(stat.modified)}   •   ${_formatSize(stat.size)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.only(left: 10, top: 10, right: 10, bottom: 10),
                      decoration: BoxDecoration(color: const Color(0xFF7C4DFF).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(_iconFor(ext), color: const Color(0xFF7C4DFF), size: 20),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
