/// User profile (first name / last name / contact email) persisted in the
/// Supabase user's metadata (Decision A, 2026-06-23).
///
/// Anonymous-auth app: there is no real account, so the profile fields live in
/// `user_metadata` — server-side, tied to the Supabase UUID, surviving app
/// relaunches (the session is restored locally). The email here is a CONTACT
/// field stored as metadata DATA — it is NOT the auth login email, so saving it
/// triggers no verification flow and does not de-anonymise the user.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfile {
  final String firstName;
  final String lastName;
  final String email;
  const UserProfile({this.firstName = '', this.lastName = '', this.email = ''});
}

class ProfileService {
  static const String _kFirst = 'first_name';
  static const String _kLast = 'last_name';
  static const String _kEmail = 'contact_email';

  /// Bumped on every successful save so widgets that render the profile (e.g.
  /// the Profile header) can refresh immediately, without a full screen rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Read the profile from the current user's metadata (empty fields if unset).
  UserProfile load() {
    final md = Supabase.instance.client.auth.currentUser?.userMetadata ??
        const <String, dynamic>{};
    String s(String k) => (md[k] as String?)?.trim() ?? '';
    return UserProfile(
      firstName: s(_kFirst),
      lastName: s(_kLast),
      email: s(_kEmail),
    );
  }

  /// Persist to user_metadata. Returns true on success; false (graceful) on
  /// failure so the UI can surface a retry without crashing.
  Future<bool> save({
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {
          _kFirst: firstName.trim(),
          _kLast: lastName.trim(),
          _kEmail: email.trim(),
        }),
      );
      revision.value++; // notify header (and any listener) to reload
      return true;
    } catch (e) {
      debugPrint('[ProfileService] save failed: $e');
      return false;
    }
  }
}
