import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'route_tracker.dart';

/// Phone GPS for a live walk or run. Read on the phone only, never stored
/// as a route and never sent anywhere: each fix becomes distance in
/// RouteTracker and is dropped.
///
/// iOS keeps updates going with the screen locked (background mode
/// `location`, blue indicator on); Android keeps them going under the
/// workout's foreground service (type `location`).
/// TODO(verify) both on a real phone with the screen off for 20 minutes.
abstract final class LocationFeed {
  /// Asks for location while in use if it hasn't been answered yet. True
  /// when fixes can be read.
  static Future<bool> ensureAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      return p == LocationPermission.whileInUse ||
          p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// True when location is already allowed, without asking.
  static Future<bool> get allowed async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.whileInUse ||
          p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Fixes about once a second until cancelled.
  static Stream<GeoFix> fixes() {
    final LocationSettings settings;
    if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else if (Platform.isAndroid) {
      // No foregroundNotificationConfig: the workout's own foreground
      // service (BackgroundGuard) carries the location type, so there's
      // one notification, not two.
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    } else {
      settings = const LocationSettings(accuracy: LocationAccuracy.best);
    }
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => GeoFix(
        p.latitude,
        p.longitude,
        accuracyM: p.accuracy,
        at: p.timestamp,
        altitudeM: p.altitude == 0 && p.altitudeAccuracy == 0
            ? null
            : p.altitude,
        altitudeAccuracyM: p.altitudeAccuracy > 0 ? p.altitudeAccuracy : null,
      ),
    );
  }
}
