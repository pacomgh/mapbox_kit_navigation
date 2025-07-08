import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

class RouteSegmentVisual {
  final String id;
  final List<mapbox.Position> coordinates;
  bool isTraversed;
  bool isHidden;
  int? stepIndex;
  final int segmentNumber;

  RouteSegmentVisual({
    required this.id,
    required this.coordinates,
    this.isHidden = false,
    this.isTraversed = false,
    this.stepIndex,
    required this.segmentNumber,
  });
}
