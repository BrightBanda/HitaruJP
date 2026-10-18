import 'package:flutter/material.dart';
import 'package:ingrain/app/theme/app_colors.dart';

/// What the user can add from the Add button. Shared by the home screen's
/// dropdown and the Add Content form.
enum AddContentType {
  youtube(
    label: 'YouTube video',
    icon: Icons.smart_display_outlined,
    color: AppColors.video,
  ),
  dialogue(
    label: 'Dialogue',
    icon: Icons.forum_outlined,
    color: AppColors.dialogue,
  );

  const AddContentType({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Every type can be added now. A type that is not ready yet can return
  /// false here to be listed as "Soon" and not pickable.
  bool get isAvailable => true;

  String get route => '/content/add?type=$name';

  static AddContentType fromName(String? name) => values.firstWhere(
    (type) => type.name == name && type.isAvailable,
    orElse: () => youtube,
  );
}
