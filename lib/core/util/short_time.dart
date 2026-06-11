/// Shared compact timestamp for feed-style rows (comments, replies, history).
library;

/// `dd/MM HH:mm` — pass a LOCAL DateTime (call `.toLocal()` at the call site).
String formatShortTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
