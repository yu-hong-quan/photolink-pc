import 'dart:async';

import 'package:flutter/foundation.dart';

/// 可取消令牌：任务执行过程中轮询 [isCancelled]
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void reset() => _cancelled = false;

  void throwIfCancelled() {
    if (_cancelled) throw const TaskCancelledException();
  }
}

class TaskCancelledException implements Exception {
  const TaskCancelledException();

  @override
  String toString() => '任务已取消';
}

/// 传输任务状态
enum TransferTaskStatus {
  pending,
  running,
  success,
  failed,
  cancelled,
}

enum TransferTaskType { upload, download }

/// 单个上传/下载任务
class TransferTask {
  TransferTask({
    required this.id,
    required this.name,
    required this.type,
    required this.execute,
    this.maxRetries = 2,
  });

  final String id;
  final String name;
  final TransferTaskType type;

  /// 实际执行逻辑；[onProgress] 回传 0~1，[token] 用于取消
  final Future<void> Function({
    required void Function(double progress, int? sent, int? total) onProgress,
    required CancelToken token,
  }) execute;

  final int maxRetries;
  final CancelToken cancelToken = CancelToken();

  TransferTaskStatus status = TransferTaskStatus.pending;
  double progress = 0;
  int? bytesSent;
  int? bytesTotal;
  String? error;
  int retryCount = 0;
  final DateTime createdAt = DateTime.now();

  bool get isUpload => type == TransferTaskType.upload;

  bool get canCancel =>
      status == TransferTaskStatus.pending ||
      status == TransferTaskStatus.running;

  bool get canRetry => status == TransferTaskStatus.failed;
}

/// 带并发限制的传输任务队列（支持取消 / 重试 / 进度）
class TransferTaskQueue extends ChangeNotifier {
  TransferTaskQueue({this.maxConcurrency = 2});

  final int maxConcurrency;
  final List<TransferTask> _tasks = [];
  int _activeWorkers = 0;
  bool _disposed = false;

  List<TransferTask> get tasks => List.unmodifiable(_tasks);

  int get pendingCount => _tasks
      .where((t) => t.status == TransferTaskStatus.pending)
      .length;

  int get runningCount => _tasks
      .where((t) => t.status == TransferTaskStatus.running)
      .length;

  int get failedCount =>
      _tasks.where((t) => t.status == TransferTaskStatus.failed).length;

  void enqueue(TransferTask task) {
    _tasks.insert(0, task);
    _notify();
    _pump();
  }

  void enqueueAll(Iterable<TransferTask> items) {
    for (final t in items) {
      _tasks.insert(0, t);
    }
    _notify();
    _pump();
  }

  /// 取消单个任务
  void cancel(String taskId) {
    TransferTask? task;
    for (final t in _tasks) {
      if (t.id == taskId) {
        task = t;
        break;
      }
    }
    if (task == null || !task.canCancel) return;
    task.cancelToken.cancel();
    if (task.status == TransferTaskStatus.pending) {
      task.status = TransferTaskStatus.cancelled;
      task.error = '已取消';
    }
    _notify();
  }

  /// 取消全部等待中 + 请求取消运行中
  void cancelAllActive() {
    for (final t in _tasks) {
      if (t.status == TransferTaskStatus.pending) {
        t.cancelToken.cancel();
        t.status = TransferTaskStatus.cancelled;
        t.error = '已取消';
      } else if (t.status == TransferTaskStatus.running) {
        t.cancelToken.cancel();
      }
    }
    _notify();
  }

  /// 失败任务重新入队
  void retry(String taskId) {
    TransferTask? task;
    for (final t in _tasks) {
      if (t.id == taskId) {
        task = t;
        break;
      }
    }
    if (task == null || !task.canRetry) return;
    _requeue(task);
  }

  void retryAllFailed() {
    for (final t in _tasks.where((e) => e.status == TransferTaskStatus.failed)) {
      _requeue(t, notify: false);
    }
    _notify();
    _pump();
  }

  void _requeue(TransferTask task, {bool notify = true}) {
    task.retryCount += 1;
    task.status = TransferTaskStatus.pending;
    task.progress = 0;
    task.error = null;
    task.bytesSent = null;
    task.bytesTotal = null;
    task.cancelToken.reset();
    if (notify) {
      _notify();
      _pump();
    }
  }

  void clearFinished() {
    _tasks.removeWhere(
      (t) =>
          t.status == TransferTaskStatus.success ||
          t.status == TransferTaskStatus.cancelled,
    );
    _notify();
  }

  void _pump() {
    while (!_disposed && _activeWorkers < maxConcurrency) {
      TransferTask? next;
      for (final t in _tasks) {
        if (t.status == TransferTaskStatus.pending) {
          next = t;
          break;
        }
      }
      if (next == null) return;
      _activeWorkers += 1;
      // 立即标记 running，避免同一任务被多次领取
      next.status = TransferTaskStatus.running;
      final current = next;
      unawaited(_run(current).whenComplete(() {
        _activeWorkers -= 1;
        if (!_disposed) _pump();
      }));
    }
    _notify();
  }

  Future<void> _run(TransferTask task) async {
    if (task.cancelToken.isCancelled) {
      task.status = TransferTaskStatus.cancelled;
      task.error = '已取消';
      _notify();
      return;
    }
    _notify();
    try {
      await task.execute(
        onProgress: (progress, sent, total) {
          if (_disposed) return;
          task.progress = progress.clamp(0.0, 1.0);
          task.bytesSent = sent;
          task.bytesTotal = total;
          _notify();
        },
        token: task.cancelToken,
      );
      if (task.cancelToken.isCancelled) {
        task.status = TransferTaskStatus.cancelled;
        task.error = '已取消';
      } else {
        task.status = TransferTaskStatus.success;
        task.progress = 1;
      }
    } on TaskCancelledException {
      task.status = TransferTaskStatus.cancelled;
      task.error = '已取消';
    } catch (e) {
      // 自动重试
      if (!task.cancelToken.isCancelled && task.retryCount < task.maxRetries) {
        task.retryCount += 1;
        task.status = TransferTaskStatus.pending;
        task.progress = 0;
        task.error = '自动重试 ${task.retryCount}/${task.maxRetries}：$e';
        task.cancelToken.reset();
        await Future<void>.delayed(
          Duration(milliseconds: 500 * task.retryCount),
        );
      } else {
        task.status = TransferTaskStatus.failed;
        task.error = '$e';
      }
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelAllActive();
    super.dispose();
  }
}
