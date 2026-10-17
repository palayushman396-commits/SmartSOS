import 'package:geolocator/geolocator.dart';

enum LocationState { ready, serviceOff, denied, deniedForever }

class LocationService {
  static Future<LocationState> check({bool request = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationState.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && request) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationState.deniedForever;
    }
    if (permission == LocationPermission.denied) {
      return LocationState.denied;
    }
    return LocationState.ready;
  }

  static String describe(LocationState state) {
    switch (state) {
      case LocationState.ready:
        return 'Location ready';
      case LocationState.serviceOff:
        return 'Location is turned off on this phone';
      case LocationState.denied:
        return 'Location permission needed';
      case LocationState.deniedForever:
        return 'Location blocked. Enable it in app settings';
    }
  }
}