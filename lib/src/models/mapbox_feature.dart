class MapboxFeature {
  final Map<String, dynamic> geometry;
  final Map<String, dynamic> properties;

  MapboxFeature({required this.geometry, required this.properties});

  Map<String, dynamic> toJson() {
    return {'type': 'Feature', 'geometry': geometry, 'properties': properties};
  }
}
