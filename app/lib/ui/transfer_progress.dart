import 'package:flutter/material.dart';

/// Counts completed items separately from work on the current item.
class TransferProgress extends ChangeNotifier {
  int done = 0;
  int total = 1;
  int failed = 0;
  double current = 0;
  String detail = '';
  String unit = 'files';

  double get fraction =>
      total == 0 ? 0 : ((done + current) / total).clamp(0, 1);

  void update(
      {int? done,
      int? total,
      double current = 0,
      String? detail,
      String? unit,
      int? failed}) {
    if (done != null) this.done = done;
    if (total != null) this.total = total;
    if (failed != null) this.failed = failed;
    this.current = current.clamp(0, 1);
    if (detail != null) this.detail = detail;
    if (unit != null) this.unit = unit;
    notifyListeners();
  }
}

class TransferMeter extends StatelessWidget {
  const TransferMeter(
      {super.key,
      required this.fraction,
      required this.done,
      required this.total,
      this.unit = 'files',
      this.failed = 0});
  final double fraction;
  final int done;
  final int total;
  final int failed;
  final String unit;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
              value: total == 0 ? null : fraction.clamp(0, 1)),
          const SizedBox(height: 12),
          Text(total == 0
              ? 'Preparing…'
              : '${(fraction * 100).floor()}% · ${done - failed} / $total $unit · '
                  '${(total - done).clamp(0, total)} remaining'),
          if (failed > 0) Text('$failed failed'),
        ],
      );
}

/// Owns its route, so cleanup cannot accidentally close another dialog.
Future<T> runTransfer<T>(BuildContext context, String title,
    Future<T> Function(TransferProgress progress) work) async {
  final progress = TransferProgress();
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: SizedBox(
              width: 420,
              child: ListenableBuilder(
                listenable: progress,
                builder: (_, __) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (progress.detail.isNotEmpty) ...[
                        Text(progress.detail,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 16),
                      ],
                      TransferMeter(
                          fraction: progress.fraction,
                          done: progress.done,
                          total: progress.total,
                          unit: progress.unit,
                          failed: progress.failed),
                    ]),
              )),
        )),
  );
  final shown = navigator.push(route);
  try {
    final result = await work(progress);
    if (progress.failed > 0 && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(
            '${progress.done - progress.failed} completed · ${progress.failed} failed'),
      ));
    }
    return result;
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    await shown;
    route.completed.then((_) => progress.dispose());
  }
}
