import 'package:flutter/material.dart';

// Заглушка для Mapbox API на веб-платформе
// Все классы и методы определены пустыми для совместимости

class MapboxMap {
  void loadStyleURI(String uri) {}
  void setCamera(CameraOptions options) {}
}

class MapboxOptions {
  static void setAccessToken(String token) {}
}

class MapboxStyles {
  static const String MAPBOX_STREETS = '';
}

class CameraOptions {
  final dynamic center;
  final double? zoom;
  
  CameraOptions({this.center, this.zoom});
}

class Point {
  final Position coordinates;
  
  Point({required this.coordinates});
  
  Map<String, dynamic> toJson() {
    return {'coordinates': coordinates};
  }
}

class Position {
  final double lng;
  final double lat;
  
  Position(this.lng, this.lat);
  
  Map<String, dynamic> toJson() {
    return {'lng': lng, 'lat': lat};
  }
}

class MapWidget extends StatelessWidget {
  final Key? key;
  final Function(MapboxMap)? onMapCreated;
  
  const MapWidget({this.key, this.onMapCreated});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      child: Center(
        child: Text('Mapbox недоступен на веб-платформе.'),
      ),
    );
  }
} 