import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/view/friends_panel.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';

/// Finds learners by @username and sends friend requests.
class SearchPeopleView extends ConsumerStatefulWidget {
  const SearchPeopleView({super.key});

  @override
  ConsumerState<SearchPeopleView> createState() => _SearchPeopleViewState();
}

class _SearchPeopleViewState extends ConsumerState<SearchPeopleView> {
  static const _debounce = Duration(milliseconds: 350);

  final _controller = TextEditingController();
  Timer? _timer;
  String _query = '';
  List<Person> _results = const [];
  bool _loading = false;
  String? _error;

  /// Usernames being acted on, so their button shows a spinner.
  final Set<String> _busy = {};

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _timer?.cancel();
    final query = text.trim().replaceFirst('@', '').toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _error = null;
      });
      return;
    }
    _timer = Timer(_debounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(socialRepositoryProvider).search(query);
      if (!mounted || query != _query) return;
      setState(() => _results = results);
    } on SocialException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reach the HitaruJP server.');
      }
    } finally {
      if (mounted && query == _query) setState(() => _loading = false);
    }
  }

  Future<void> _act(Person person) async {
    final container = ref.container;
    final repository = container.read(socialRepositoryProvider);
    setState(() => _busy.add(person.username));
    try {
      final Person updated;
      switch (person.relation) {
        case Relation.incoming:
          updated = await repository.acceptFriend(person.username);
        case Relation.outgoing:
          // Tapping "Requested" takes the request back.
          await repository.removeFriend(person.username);
          updated = person.withRelation(Relation.none);
        case Relation.none || Relation.friends:
          updated = await repository.addFriend(person.username);
      }
      HapticFeedback.selectionClick();
      if (!mounted) return;
      setState(() {
        _results = [
          for (final result in _results)
            result.username == person.username ? updated : result,
        ];
      });
      container
        ..invalidate(socialSummaryProvider)
        ..invalidate(leaderboardProvider);
    } on SocialException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reach the HitaruJP server.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(person.username));
    }
  }

  Widget _button(Person person) {
    if (_busy.contains(person.username)) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    return switch (person.relation) {
      Relation.friends => const Chip(label: Text('Friends')),
      Relation.outgoing => OutlinedButton(
        onPressed: () => _act(person),
        child: const Text('Requested'),
      ),
      Relation.incoming => FilledButton(
        onPressed: () => _act(person),
        child: const Text('Accept'),
      ),
      Relation.none => FilledButton.icon(
        onPressed: () => _act(person),
        icon: const Icon(Icons.person_add, size: 18),
        label: const Text('Add'),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Find people')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                prefixText: '@',
                hintText: 'username',
              ),
              onChanged: _changed,
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _query.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Search by username. Ask your friends for theirs, or '
                      'share yours from the Friends page.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : _error != null
                ? Center(child: Text(_error!))
                : _results.isEmpty && !_loading
                ? Center(child: Text('No one found for "@$_query".'))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final person in _results)
                        PersonRow(person: person, actions: [_button(person)]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
