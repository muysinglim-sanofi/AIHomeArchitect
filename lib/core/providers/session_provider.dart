import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/models/project_model.dart';

class SessionNotifier extends StateNotifier<List<ProjectModel>> {
  SessionNotifier() : super(List.from(mockProjects));

  void updateTitle(String id, String title) {
    state = [
      for (final p in state)
        if (p.id == id)
          p.copyWith(title: title, lastUpdatedAt: DateTime.now())
        else
          p,
    ];
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, List<ProjectModel>>(
  (ref) => SessionNotifier(),
);
