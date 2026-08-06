import 'package:flutter/material.dart';

import '../services/transfer_task_queue.dart';
import '../theme/app_theme.dart';

/// V1.1 任务队列面板：进度 / 取消 / 重试 / 清理
class TaskQueuePanel extends StatelessWidget {
  const TaskQueuePanel({super.key, required this.queue});

  final TransferTaskQueue queue;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final tasks = queue.tasks;
        if (tasks.isEmpty) return const SizedBox.shrink();
        return Material(
          elevation: 10,
          color: Colors.white,
          child: SizedBox(
            height: 168,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                  child: Row(
                    children: [
                      const Text(
                        '传输任务',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '进行中 ${queue.runningCount} · 等待 ${queue.pendingCount}'
                        '${queue.failedCount > 0 ? ' · 失败 ${queue.failedCount}' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5A6F6D),
                        ),
                      ),
                      const Spacer(),
                      if (queue.failedCount > 0)
                        TextButton(
                          onPressed: queue.retryAllFailed,
                          child: const Text('全部重试'),
                        ),
                      TextButton(
                        onPressed: queue.cancelAllActive,
                        child: const Text('全部取消'),
                      ),
                      TextButton(
                        onPressed: queue.clearFinished,
                        child: const Text('清理完成'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final t = tasks[index];
                      return _TaskTile(task: t, queue: queue);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.queue});

  final TransferTask task;
  final TransferTaskQueue queue;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        task.isUpload ? Icons.upload_rounded : Icons.download_rounded,
        color: PhotoLinkTheme.brand,
      ),
      title: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.status == TransferTaskStatus.running ||
                      task.status == TransferTaskStatus.pending
                  ? (task.progress <= 0 ? null : task.progress)
                  : task.progress,
              minHeight: 5,
              backgroundColor: const Color(0xFFE6EEEC),
              color: _barColor(task.status),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _statusText(task),
            style: TextStyle(
              fontSize: 11,
              color: task.status == TransferTaskStatus.failed
                  ? Colors.red.shade700
                  : const Color(0xFF5A6F6D),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (task.canCancel)
            IconButton(
              tooltip: '取消',
              onPressed: () => queue.cancel(task.id),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          if (task.canRetry)
            IconButton(
              tooltip: '重试',
              onPressed: () => queue.retry(task.id),
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
        ],
      ),
    );
  }

  Color _barColor(TransferTaskStatus s) {
    switch (s) {
      case TransferTaskStatus.success:
        return const Color(0xFF1FA87A);
      case TransferTaskStatus.failed:
        return Colors.redAccent;
      case TransferTaskStatus.cancelled:
        return Colors.grey;
      default:
        return PhotoLinkTheme.brand;
    }
  }

  String _statusText(TransferTask t) {
    final bytes = _bytesLabel(t);
    switch (t.status) {
      case TransferTaskStatus.pending:
        return t.error ?? '等待中$bytes';
      case TransferTaskStatus.running:
        return '进行中 ${(t.progress * 100).toStringAsFixed(0)}%$bytes';
      case TransferTaskStatus.success:
        return '完成$bytes';
      case TransferTaskStatus.failed:
        return '失败：${t.error ?? ''}';
      case TransferTaskStatus.cancelled:
        return '已取消';
    }
  }

  String _bytesLabel(TransferTask t) {
    if (t.bytesSent == null) return '';
    final sent = _fmt(t.bytesSent!);
    if (t.bytesTotal == null || t.bytesTotal! <= 0) return ' · $sent';
    return ' · $sent / ${_fmt(t.bytesTotal!)}';
  }

  String _fmt(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
