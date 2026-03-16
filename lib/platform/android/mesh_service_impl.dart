/// Android [MeshService] backed by `connectivity_plus`.
///
/// Overrides `isConnected` to use `connectivity_plus` which uses
/// Android NetworkCallback for accurate connectivity state.
library;

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:kabuk/platform/shared/mesh_service_impl.dart';
import 'package:kabuk/services/mesh.dart';

/// Android [MeshService] using `connectivity_plus` for connectivity checks.
class AndroidMeshService extends SharedMeshService implements MeshService {
  /// Creates an [AndroidMeshService].
  AndroidMeshService({super.client});

  final _connectivity = Connectivity();

  @override
  Future<bool> get isConnected async {
    try {
      final result = await _connectivity.checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } on Object {
      // Fallback: DNS check.
      try {
        final lookup = await InternetAddress.lookup('example.com');
        return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
      } on SocketException {
        return false;
      }
    }
  }
}
