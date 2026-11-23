import 'package:flutter/material.dart';
import 'package:ingrain/features/growth/presentation/mascot_painter.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/social/domain/social.dart';

/// A learner as their companion, at the stage it has grown to.
class PersonAvatar extends StatelessWidget {
  final Person person;
  final double size;

  const PersonAvatar({super.key, required this.person, this.size = 44});

  @override
  Widget build(BuildContext context) => MascotPortrait(
    character: person.avatarId == null
        ? AvatarCharacter.kitsune
        : AvatarCharacter.fromId(person.avatarId),
    stage: person.stats.stage,
    size: size,
  );
}

/// `Lv 12 · 🔥 14`.
String statsLine(Person person) {
  final stats = person.stats;
  return [
    'Lv ${stats.level}',
    if (stats.streak > 0) '🔥 ${stats.streak}',
  ].join(' · ');
}
