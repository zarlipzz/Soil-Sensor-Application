import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// TileProvider compatible with flutter_map v6+.
///
/// In test mode returns a transparent 1×1 PNG.
/// In production delegates to [NetworkTileProvider] (bundled with flutter_map).
class NonNetworkTileProvider extends TileProvider {
  NonNetworkTileProvider();

  static final Uint8List _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/QLyU0cAAAAASUVORK5CYII=',
  );

  static bool get _isTest =>
      !kReleaseMode &&
      (bool.fromEnvironment('FLUTTER_TEST', defaultValue: false) ||
          const String.fromEnvironment('FLUTTER_TEST').isNotEmpty);

  // flutter_map v6 uses getImageWithCancelLoadingSupport / getImage.
  // We override supportsCancelLoading = false and implement getImage.
  @override
  bool get supportsCancelLoading => false;

  @override
  ImageProvider<Object> getImage(TileCoordinates coordinates, TileLayer options) {
    if (_isTest) {
      return MemoryImage(_transparentPng);
    }
    final url =
        'https://tile.openstreetmap.org/${coordinates.z}/${coordinates.x}/${coordinates.y}.png';
    return NetworkImage(url, headers: {'User-Agent': 'soil_app/1.0'});
  }
}

