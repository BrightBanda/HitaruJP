/// What the learner wants to be pushed about, and when.
///
/// Kept on the phone and sent to the server with its push token, since the
/// server does the sending.
class NotificationSettings {
  /// The hour of day (0-23, local time) the daily message goes out.
  final int reminderHour;

  /// "Your streak ends tonight", only when a streak is worth protecting.
  final bool streakAlerts;

  /// The daily nudge to study when nothing was done yet.
  final bool reminders;

  /// One message after 3 and after 7 days away.
  final bool winback;

  const NotificationSettings({
    this.reminderHour = 19,
    this.streakAlerts = true,
    this.reminders = true,
    this.winback = true,
  });

  NotificationSettings copyWith({
    int? reminderHour,
    bool? streakAlerts,
    bool? reminders,
    bool? winback,
  }) {
    return NotificationSettings(
      reminderHour: reminderHour ?? this.reminderHour,
      streakAlerts: streakAlerts ?? this.streakAlerts,
      reminders: reminders ?? this.reminders,
      winback: winback ?? this.winback,
    );
  }

  /// Whether anything at all would be sent.
  bool get anyOn => streakAlerts || reminders || winback;

  @override
  bool operator ==(Object other) =>
      other is NotificationSettings &&
      other.reminderHour == reminderHour &&
      other.streakAlerts == streakAlerts &&
      other.reminders == reminders &&
      other.winback == winback;

  @override
  int get hashCode =>
      Object.hash(reminderHour, streakAlerts, reminders, winback);
}
