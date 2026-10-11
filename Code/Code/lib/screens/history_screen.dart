import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../models/emergency_record.dart';
import '../services/storage_service.dart';

/// Displays the locally-stored history of emergency alerts.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final StorageService _storageService = StorageService();
  List<EmergencyRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await _storageService.getHistory();
    if (!mounted) return;
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  Future<void> _clear() async {
    await _storageService.clearHistory();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Emergency History'),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.charcoal,
        elevation: 0,
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              tooltip: 'Clear history',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.lime))
          : _records.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _records.length,
              itemBuilder: (context, index) =>
                  _buildRecordCard(_records[index]),
            ),
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        title: const Text(
          'Clear History',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('Delete all stored emergency records?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _clear();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.limeSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history,
              size: 64,
              color: AppTheme.limeDark,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No emergency alerts yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.charcoal,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Alerts you send will appear here',
            style: TextStyle(fontSize: 14, color: AppTheme.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(EmergencyRecord r) {
    final delivered = r.deliveredCount == r.contactCount && r.contactCount > 0;
    final statusColor = delivered ? AppTheme.success : AppTheme.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            delivered ? Icons.check_circle : Icons.warning_amber_rounded,
            color: statusColor,
          ),
        ),
        title: Text(
          r.triggerType,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              _formatDate(r.timestamp),
              style: const TextStyle(color: AppTheme.grey, fontSize: 12),
            ),
            Text(
              r.status,
              style: const TextStyle(
                color: AppTheme.charcoalSoft,
                fontSize: 13,
              ),
            ),
            if (r.hasLocation)
              Text(
                'Loc: ${r.latitude!.toStringAsFixed(4)}, ${r.longitude!.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.grey),
              ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day}/${d.month}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}
