import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math' show cos, sqrt, asin;
import 'package:uuid/uuid.dart';

import 'package:mapbox_kit_navigation/src/models/mapbox_model.dart'
    as mapbox_model;
import 'package:mapbox_kit_navigation/mapbox_kit_navigation.dart';

class NavigationMap extends StatefulWidget {
  final String mapboxAccessToken;
  final bool showSearchBar;
  final List<List<double>>? routeCoordinatesList;

  const NavigationMap({
    super.key,
    required this.mapboxAccessToken,
    this.showSearchBar = true,
    this.routeCoordinatesList,
  });

  @override
  State<NavigationMap> createState() => _NavigationMapState();
}

class _NavigationMapState extends State<NavigationMap> {
  //to realtime location
  StreamSubscription<geo.Position>? positionStreamSubscription;
  //to draw user market
  mapbox.PointAnnotation? userMarker;
  //to add annotations to map
  mapbox.PointAnnotationManager? pointAnnotationManager;
  String coordinates = '';

  mapbox.MapboxMap? _mapboxMapController;
  geo.Position? _currentPosition;

  // List<List<double>> _routeCoordinates = [];
  List<dynamic> mapboxGeometry = [];

  List<mapbox.Point> selectedPoints = [];
  //to store final coordinates and steps
  List<mapbox.Position> routeCoordinates = [];
  List<mapbox.Position> routeSegmentsCoordinates = [];
  List<dynamic> _routeSteps = [];
  int _currentRouteStepIndex = 0;
  FlutterTts flutterTts = FlutterTts();
  bool _isNavigating = false;

  //to list traffic segments
  mapbox_model.MapboxModel? mapboxModel;
  List<int> trafficIndexesList = [];
  List<MapboxFeature> trafficSegments = [];
  List<String> congestionList = [];

  //to search places
  // Lista para guardar info del lugar
  List<Map<String, dynamic>> _addedLocations = [];
  final TextEditingController _searchController = TextEditingController();
  // --- Para la funcionalidad de búsqueda nativa ---
  List<Map<String, dynamic>> _suggestions = []; // Lista para las sugerencias
  Timer? _debounce; // Para el debounce de la búsqueda

  //spoken steps
  // En _NavigationMapState (añade esta variable)
  bool _hasSpokenInstructionForCurrentStep = false;

  mapbox.PolylineAnnotationManager? _polylineAnnotationManager;

  int currentIndexStep = 0;

  late final featureCollection;
  List<mapbox.Feature> features = [];
  int indexRemoveSedmentPolyline = 0;
  // Cantidad de segmentos a dibujar
  final int _segmentPointsThreshold = 5;

  int lastConsumedSegmentIndex = -1;
  // Nueva lista para nuestros segmentos lógicos
  List<RouteSegmentVisual> routeVisualSegments = [];
  // Asegúrate de que esta lista esté disponible

  // Para la ruta recorrida
  // Ruta base (gris)
  mapbox.PolylineAnnotation? _traversedPolyline;
  // Para la ruta no recorrida (base)
  // Ruta recorrida (azul)
  mapbox.PolylineAnnotation? _unTraversedPolyline;
  // Nuevo: El índice del último segmento lógico recorrido
  int _lastTraversedSegmentIndex = -1;
  bool _isMapReady = false;
  int highestTraversedPointIndex = -1;

  // Asegúrate de inicializar Uuid
  final Uuid uuid = Uuid();

  // Para almacenar los marcadores de destino
  List<mapbox.PointAnnotation> _destinationMarkers = [];

  // final String _userSourceId = 'user-location-source';
  // final String _userLayerId = 'user-location-layer';

  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    mapbox.MapboxOptions.setAccessToken(widget.mapboxAccessToken);
    // _requestLocationPermission();
    Future.delayed(Duration.zero, () async {
      await _requestLocationPermission();
    });
    _initTextToSpeech();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            // _currentPosition == null
            _isInitializing
                ? const Center(child: CircularProgressIndicator())
                : mapbox.MapWidget(
                    cameraOptions: mapbox.CameraOptions(
                      center: mapbox.Point(
                        coordinates: mapbox.Position(
                          _currentPosition!.longitude,
                          _currentPosition!.latitude,
                        ),
                      ),
                      zoom: 15.0,
                    ),
                    onMapCreated: (controller) async {
                      print('🌟 creando mapa');
                      _mapboxMapController = controller;
                      _isMapReady = true;

                      await _mapboxMapController!.location.updateSettings(
                        mapbox.LocationComponentSettings(enabled: false),
                      );

                      await _addImageToStyle(
                        'user_marker_id',
                        'lib/mapbox_kit_navigation/assets/user_marker.png',
                      );
                      await _addImageToStyle(
                        'navigation_marker_id',
                        'lib/mapbox_kit_navigation/assets/navigation.png',
                      );

                      pointAnnotationManager ??= await _mapboxMapController!
                          .annotations
                          .createPointAnnotationManager();
                      await _initializeMapAndLocation();
                      print('DEBUG: PointAnnotationManager inicializado.');

                      setState(() {
                        _isMapReady = true;
                      });
                    },
                    onStyleLoadedListener: (style) async {},
                  ),
            widget.showSearchBar
                ? Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Material(
                      elevation: 4.0,
                      borderRadius: BorderRadius.circular(8.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Buscar lugar...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _suggestions =
                                              []; // Limpiar sugerencias
                                        });
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 0,
                                horizontal: 10,
                              ),
                            ),
                            onChanged: (val) {
                              // Si el campo tiene texto, re-mostrar sugerencias al tocarlo
                              if (_searchController.text.isNotEmpty &&
                                  _suggestions.isEmpty) {
                                // _getPlaceSuggestions(_searchController.text);
                                _getPlaceSuggestions(val);
                              }
                            },
                          ),
                          // Lista de sugerencias (se muestra solo si hay sugerencias)
                          if (_suggestions.isNotEmpty)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.3,
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _suggestions.length,
                                itemBuilder: (context, index) {
                                  final suggestion = _suggestions[index];
                                  return ListTile(
                                    title: Text(suggestion['name']),
                                    onTap: () {
                                      // print(
                                      //   'suggestion 💔 ${_searchController.text}',
                                      // );
                                      _onSuggestionSelected(suggestion);
                                    },
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : SizedBox.shrink(),
            // Lista de coordenadas agregadas
            widget.showSearchBar
                ? Positioned(
                    bottom: 10,
                    left: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8.0),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4.0,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.3,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lugares Agregados:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_addedLocations.isEmpty)
                            const Text('Aún no has agregado lugares.')
                          else
                            Expanded(
                              child: ListView.builder(
                                itemCount: _addedLocations.length,
                                itemBuilder: (context, index) {
                                  // print('🌻 added locations ${_addedLocations[index]}');
                                  final location = _addedLocations[index];
                                  final double lng =
                                      location['point'].coordinates.lng;
                                  final double lat =
                                      location['point'].coordinates.lat;
                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4.0,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            SizedBox(
                                              width: MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  .7,
                                              child: Text(
                                                '${location['name']} (Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)})',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                // Asegúrate de pasar la referencia al marcador y el índice
                                                final markerReference =
                                                    location['marker'] as mapbox
                                                        .PointAnnotation?;
                                                if (markerReference != null) {
                                                  _removeSingleDestinationMarker(
                                                    markerReference,
                                                    index,
                                                  );
                                                } else {
                                                  // Si por alguna razón la referencia al marcador no está,
                                                  // aún puedes intentar remover por índice (menos seguro)
                                                  setState(() {
                                                    _addedLocations.removeAt(
                                                      index,
                                                    );
                                                    selectedPoints.removeAt(
                                                      index,
                                                    );
                                                  });
                                                  // print(
                                                  //   '⚠️ No se encontró referencia al marcador para eliminarlo del mapa.',
                                                  // );
                                                }
                                              },
                                              child: Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Divider(
                                          color: Colors.grey, thickness: .5),
                                    ],
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : SizedBox.shrink(),
            //botones de zoom
            Positioned(
              top: 60,
              bottom: 150,
              right: 20,
              child: Column(
                children: [
                  FloatingActionButton(
                    heroTag: "zoomInBtn",
                    onPressed: _zoomIn,
                    mini: true,
                    child: const Icon(Icons.add),
                  ),
                  FloatingActionButton(
                    heroTag: "zoomOutBtn",
                    onPressed: _zoomOut,
                    mini: true,
                    child: const Icon(Icons.remove),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 160,
              right: 20,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_isNavigating)
                    FloatingActionButton(
                      // onPressed: () {},
                      onPressed: _startNavigation,
                      child: const Icon(Icons.navigation),
                    ),
                  if (_isNavigating)
                    FloatingActionButton(
                      onPressed: _stopNavigation,
                      child: const Icon(Icons.stop),
                    ),
                  SizedBox(height: 2),
                  FloatingActionButton(
                    onPressed: () {
                      _updateCameraPosition(
                        mapbox.Position(
                          _currentPosition!.longitude,
                          _currentPosition!.latitude,
                        ),
                      );
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initializeMapAndLocation() async {
    // Asegúrate de que el controlador del mapa y el mapa estén listos antes de continuar
    if (_mapboxMapController == null || !_isMapReady) {
      print(
        '⚠️ _initializeMapAndLocation: El mapa aún no está listo. Reintentando en breve...',
      );
      // Opcional: Podrías usar un Future.delayed o un listener para reintentar
      return;
    }

    // print(
    //   '🗺️ _initializeMapAndLocation: Mapa listo, iniciando proceso de ubicación.',
    // );

    // 2. Si los permisos están concedidos, inicia la obtención y actualización de la ubicación
    // print(
    //   '✅ _initializeMapAndLocation: Permisos de ubicación concedidos. Iniciando getCurrentLocation...',
    // );
    await _getCurrentLocation();

    if (_currentPosition != null) {
      _mapboxMapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              _currentPosition!.longitude,
              _currentPosition!.latitude,
            ),
          ),
          zoom: 15.0,
          bearing: _currentPosition!.heading,
          pitch: 0.0,
        ),
        mapbox.MapAnimationOptions(duration: 1000),
      );
      // print(
      //   '🗺️ _initializeMapAndLocation: Cámara movida a la posición inicial del usuario.',
      // );
    } else {
      // print(
      //   'ℹ️ _initializeMapAndLocation: _currentPosition es nulo, no se pudo mover la cámara inicialmente.',
      // );
    }
  }

  //all functional methods
  Future<void> _addImageToStyle(String imageId, String assetPath) async {
    if (_mapboxMapController == null) {
      // print('⚠️ _addImageToStyle: MapboxMapController no está inicializado.');
      return;
    }

    final ByteData bytes = await rootBundle.load(assetPath);
    final Uint8List list = bytes.buffer.asUint8List();

    final mapbox.MbxImage mbxImage = mapbox.MbxImage(
      width: 96,
      height: 96,
      data: list,
    );

    try {
      // Intenta añadir la imagen. Si ya existe, esto lanzará una excepción.
      await _mapboxMapController!.style.addStyleImage(
        imageId, // 1. String imageId
        1.0, // 2. double scale (usamos 1.0 para escala normal)
        mbxImage, // 3. MbxImage image (nuestro objeto MbxImage)
        false, // 4. bool sdf (false para imágenes que no son Signed Distance Field)
        [], // 5. List<ImageStretches?> stretchX (vacía si no necesitas estirar)
        [], // 6. List<ImageStretches?> stretchY (vacía si no necesitas estirar)
        null, // 7. ImageContent? content (null si no necesitas contenido especial)
      );
      print('✅ Imagen "$imageId" añadida al estilo del mapa.');
    } catch (e) {
      _showSnackBar(
        'Imagen "$imageId" ya existe o hubo un error al añadirla: $e. Continuando...',
      );
      // print(
      //   'ℹ️ Imagen "$imageId" ya existe o hubo un error al añadirla: $e. Continuando...',
      // );
      // Puedes inspeccionar 'e' si quieres loguear errores específicos que no sean de existencia.
    }
  }

  Future<void> _initTextToSpeech() async {
    await flutterTts.setLanguage('es-MX');
    await flutterTts.setSpeechRate(0.4);
  }

  Future<void> _requestLocationPermission() async {
    // print('🌟🌟🌟🌟 request epermision');
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      await _getCurrentLocation();
    } else {
      _showSnackBar('Permiso de ubicación denegado.');
      // print('Permiso de ubicación denegado.');
    }
  }

  // Un método auxiliar para mostrar SnackBar
  void _showSnackBar(String message) {
    if (mounted && ScaffoldMessenger.of(context).mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    // print('㊗️ Iniciando _getCurrentLocation...');
    try {
      _mapboxMapController?.location.updateSettings(
        mapbox.LocationComponentSettings(enabled: false),
      );
      const geo.LocationSettings locationSettings = geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5,
      );

      geo.Position initialPosition = await geo.Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      _currentPosition = initialPosition;
      setState(() {
        _isInitializing = false;
      });
      // print(
      //   '🌟 Posición inicial obtenida: Lat ${_currentPosition!.latitude}, Lng ${_currentPosition!.longitude}',
      // );

      await _updateUserLocationLayer(
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
        bearing: _currentPosition!.heading,
      );
      // print('📍 Marcador de usuario inicial (SymbolLayer) creado.');

      // print('📍 Marcador de usuario inicial creado.');

      // 4. Mover la cámara a la posición inicial
      if (_mapboxMapController != null) {
        _updateCameraPosition(
          mapbox.Position(
            _currentPosition!.longitude,
            _currentPosition!.latitude,
          ),
        );
        // print('🗺️ Cámara movida a la posición inicial.');
      }

      // 5. Iniciar el stream de actualizaciones de posición
      positionStreamSubscription = geo.Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (geo.Position position) async {
          _currentPosition = position;
          print(
            '👮‍♀️👮‍♀️👮‍♀️👮‍♀️👮‍♀️ Ubicación actualizada en stream: Lat ${position.latitude}, Lng ${position.longitude}',
          );

          // Determinar qué asset usar para el marcador basado en _isNavigating
          // final String markerAsset = _isNavigating
          //     ? 'lib/mapbox_kit_navigation/assets/navigation.png'
          //     : 'lib/mapbox_kit_navigation/assets/user_marker.png';

          await _updateUserLocationLayer(
            lat: _currentPosition!.latitude,
            lng: _currentPosition!.longitude,
            bearing: _currentPosition!.heading,
          );

          // Lógica de navegación (perspectiva y progreso)
          if (_isNavigating) {
            _setNavigationPerspective(
              targetLat: _currentPosition!.latitude,
              targetLng: _currentPosition!.longitude,
              // Ajustar el rumbo de la cámara
              bearing: _currentPosition!.heading,
            );
            _checkRouteProgress(); //
          }
          setState(() {});
        },
        onError: (error) {
          _showSnackBar(' Error al obtener la ubicación en tiempo real $error');
          // print('Error al obtener la ubicación en stream: $error');
        },
      );
    } catch (e) {
      _showSnackBar(' Error al obtener la ubicación');
      // print('❌ Error al obtener la ubicación (try/catch principal): $e');
    }
  }

  Future<void> _updateUserLocationLayer({
    required double lat,
    required double lng,
    required double bearing,
  }) async {
    if (_mapboxMapController == null || pointAnnotationManager == null) return;

    final String markerAsset = _isNavigating
        ? 'lib/mapbox_kit_navigation/assets/navigation.png'
        : 'lib/mapbox_kit_navigation/assets/user_marker.png';

    final ByteData bytes = await rootBundle.load(markerAsset);
    final Uint8List list = bytes.buffer.asUint8List();

    // Prepara las opciones para el marcador
    final updatedMarkerOptions = mapbox.PointAnnotationOptions(
      geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      image: list,

      // iconRotate: bearing, // Mapbox PointAnnotation no tiene un 'iconRotate' directo para el bearing como SymbolLayer
    );

    final mapbox.Point newGeometry = mapbox.Point(
      coordinates: mapbox.Position(lng, lat),
    );

    if (userMarker == null) {
      // Si el marcador del usuario no existe, créalo por primera vez
      userMarker = await pointAnnotationManager!.create(updatedMarkerOptions);
      // print('📍 Marcador de usuario (PointAnnotation) creado.');
    } else {
      userMarker!.geometry = newGeometry;
      userMarker!.image = list;

      await pointAnnotationManager!.update(userMarker!);
    }
  }

  void _updateCameraPosition(mapbox.Position latLng) {
    _mapboxMapController?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(latLng.lng, latLng.lat),
        ),
        zoom: 15.0,
      ),
      mapbox.MapAnimationOptions(duration: 1000),
    );
  }

  Future<void> _getRoute() async {
    // print('🌟 get route');
    final String baseUrl =
        'https://api.mapbox.com/directions/v5/mapbox/driving';

    List<mapbox.Point> pointsForDirectionsApi = [];

    // Decidir qué puntos usar para la petición a la API de Directions
    if (!widget.showSearchBar &&
        widget.routeCoordinatesList != null &&
        widget.routeCoordinatesList!.isNotEmpty) {
      pointsForDirectionsApi.addAll(
        widget.routeCoordinatesList!
            .map(
              (coords) => mapbox.Point(
                coordinates: mapbox.Position(coords[0], coords[1]),
              ),
            )
            .toList(),
      );
      // print(
      //   'DEBUG: Usando puntos de ruta proporcionados al constructor de la biblioteca.',
      // );
    } else if (widget.showSearchBar && selectedPoints.isNotEmpty) {
      // Si hay barra de búsqueda, usamos los puntos seleccionados por el usuario.
      pointsForDirectionsApi.addAll(selectedPoints);
      // print('DEBUG: Usando puntos de ruta seleccionados por el usuario.');
    } else {
      // Caso de error: no hay puntos ni predefinidos ni seleccionados
      // print(
      //   '🖐️ Advertencia: No hay puntos de ruta para calcular. No se pudo iniciar la navegación.',
      // );
      _showSnackBar(
        'No hay puntos de ruta válidos. Por favor, selecciona o proporciona puntos.',
      );
      _removePolyline();
      highestTraversedPointIndex = -1;
      setState(() {
        routeCoordinates.clear();
        _routeSteps.clear();
        _currentRouteStepIndex = 0;
        _isNavigating = false;
      });
      return;
    }

    selectedPoints.insert(
      0,
      mapbox.Point(
        coordinates: mapbox.Position(
          _currentPosition!.longitude,
          _currentPosition!.latitude,
        ),
      ),
    );

    if (selectedPoints.length < 2) {
      // print(
      //   '🖐️ Advertencia: Necesitas seleccionar al menos un lugar para calcular una ruta.',
      // );
      // Limpia cualquier ruta anterior si es necesario
      _removePolyline(); // Reusa la función de limpieza de polilíneas
      highestTraversedPointIndex = -1; // Reiniciar
      setState(() {
        routeCoordinates.clear(); // Limpiar
        routeSegmentsCoordinates.clear(); // Limpiar
        _routeSteps.clear(); // Limpiar
        _currentRouteStepIndex = 0;
        _isNavigating = false;
      });
      return;
    }

    // print('🌟 coordinates ${selectedPoints.length}');
    String coordinatesString = selectedPoints
        .map((point) => '${point.coordinates.lng},${point.coordinates.lat}')
        .join(';');

    final String accessToken = widget.mapboxAccessToken;
    final String url =
        '$baseUrl/$coordinatesString?access_token=$accessToken&geometries=geojson&overview=full&steps=true&language=es&annotations=congestion';
    // print('🌟 url $url');
    // print('🌟 url ${await http.get(Uri.parse(url))}');

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          // print('✅ Ruta obtenida exitosamente.');

          // *** CAMBIO CLAVE AQUÍ: Asigna el modelo una sola vez ***
          mapboxModel = mapbox_model.mapboxModelFromJson(response.body);
          // print('DEBUG: mapboxModel asignado.');

          // Accede a la ruta principal del modelo
          final mapbox_model.Route? route = mapboxModel!.routes?.first;

          if (route != null) {
            // Poblar routeCoordinates directamente desde la geometría de la ruta principal
            if (route.geometry?.coordinates != null) {
              routeCoordinates = route.geometry!.coordinates!
                  .map(
                    (coordPair) => mapbox.Position(coordPair[0], coordPair[1]),
                  )
                  .toList();
              // print(
              //   'DEBUG: routeCoordinates poblada con ${routeCoordinates.length} puntos desde el modelo.',
              // );
            } else {
              // print(
              //   '⚠️ Advertencia: route.geometry.coordinates es nulo o vacío en el modelo.',
              // );
              // Puedes tener un fallback aquí si realmente necesitas iterar sobre los steps si la geometría principal falta.
              // Por ahora, confiaremos en overview=full para llenar route.geometry.coordinates.
              routeCoordinates.clear();
            }

            // Poblar _routeSteps desde el modelo (combinando todos los steps de todos los legs)
            _routeSteps.clear();
            if (route.legs != null) {
              for (var leg in route.legs!) {
                if (leg.steps != null) {
                  _routeSteps.addAll(leg.steps!.map((s) => s.toJson()));
                }
              }
            }
            // print('DEBUG: _routeSteps tiene ${_routeSteps.length} pasos.');

            // Procesar información de tráfico y crear segmentos
            await getTrafficList(route); // Pasa la ruta del modelo directamente
            await createCoordinatesSegments(
              legList: route.legs!,
            ); // Pasa los legs del modelo
            print(
              'DEBUG: getTrafficList y createCoordinatesSegments completados.',
            );
          } else {
            // print('⚠️ El modelo no contiene rutas válidas.');
            routeCoordinates.clear();
            _routeSteps.clear();
            routeVisualSegments.clear();
            trafficSegments.clear();
            highestTraversedPointIndex = -1;
          }

          setState(() {
            _currentRouteStepIndex = 0;
            _hasSpokenInstructionForCurrentStep = false;
          });

          // Llamada a _addRouteToMap()
          await _addPolyline();
          // print('DEBUG: _addRouteToMap() completado desde _getRoute().');
        } else {
          // print(
          //   '⚠️ No se encontraron rutas válidas en la respuesta de Mapbox.',
          // );
          _showSnackBar(
            'No se pudo encontrar una ruta para los puntos seleccionados.',
          );
          routeCoordinates.clear();
          _routeSteps.clear();
          routeVisualSegments.clear();
          trafficSegments.clear();
          highestTraversedPointIndex = -1;
        }
      } else {
        String errorMessage =
            'Error al obtener la ruta. Código: ${response.statusCode}';
        if (response.body.isNotEmpty) {
          try {
            final errorData = jsonDecode(response.body);
            if (errorData['message'] != null) {
              errorMessage += '\nMensaje: ${errorData['message']}';
            }
          } catch (e) {
            errorMessage += '\nRespuesta: ${response.body}';
          }
        }
        // print('❌ $errorMessage');
        _showSnackBar(errorMessage);
        routeCoordinates.clear();
        _routeSteps.clear();
        routeVisualSegments.clear();
        trafficSegments.clear();
        highestTraversedPointIndex = -1;
      }
    } catch (e) {
      // print('❌ Excepción al obtener la ruta: $e');
      _showSnackBar(
        'Ocurrió un error al intentar obtener la ruta. Verifica tu conexión.',
      );
      routeCoordinates.clear();
      _routeSteps.clear();
      routeVisualSegments.clear();
      trafficSegments.clear();
      highestTraversedPointIndex = -1;
      clearRouteRlatedState();
    }
  }

  Future<void> getTrafficList(mapbox_model.Route routeModel) async {
    // print(
    //   '🌟 getTrafficList: Procesando niveles de congestión para la ruta...',
    // );

    // Limpiar listas anteriores antes de rellenar
    congestionList.clear();
    trafficIndexesList.clear();
    trafficSegments.clear(); // Limpiamos los segmentos de tráfico anteriores

    if (routeModel.legs == null || routeModel.legs!.isEmpty) {
      // print(
      //   '⚠️ Advertencia: No hay legs en el modelo de ruta para procesar congestión.',
      // );
      return;
    }

    List<mapbox.Position> fullRouteCoordinatesFromModel = [];

    if (routeModel.geometry != null &&
        routeModel.geometry!.coordinates != null) {
      fullRouteCoordinatesFromModel = routeModel.geometry!.coordinates!
          .map((coordPair) => mapbox.Position(coordPair[0], coordPair[1]))
          .toList();
    } else {
      for (var leg in routeModel.legs!) {
        if (leg.steps != null) {
          for (var step in leg.steps!) {
            if (step.geometry != null && step.geometry!.coordinates != null) {
              for (var coordPair in step.geometry!.coordinates!) {
                fullRouteCoordinatesFromModel.add(
                  mapbox.Position(coordPair[0], coordPair[1]),
                );
              }
            }
          }
        }
      }
    }

    int globalCoordinateIndex = 0;

    for (int legIndex = 0; legIndex < routeModel.legs!.length; legIndex++) {
      final currentLeg = routeModel.legs![legIndex];

      if (currentLeg.annotation == null ||
          currentLeg.annotation!.congestion == null) {
        // print(
        //   'ℹ️ Leg $legIndex no tiene anotaciones de congestión. Saltando este leg.',
        // );

        if (currentLeg.steps != null) {
          for (var step in currentLeg.steps!) {
            if (step.geometry != null && step.geometry!.coordinates != null) {
              globalCoordinateIndex += step.geometry!.coordinates!.length;
            }
          }
        }
        continue;
      }

      final List<mapbox_model.Congestion> congestionLevelsForLeg =
          currentLeg.annotation!.congestion!;

      for (int i = 0; i < congestionLevelsForLeg.length; i++) {
        String currentCongestionLevelString = "unknown";
        switch (congestionLevelsForLeg[i]) {
          case mapbox_model.Congestion.LOW:
            currentCongestionLevelString = "low";
            break;
          case mapbox_model.Congestion.MODERATE:
            currentCongestionLevelString = "moderate";
            break;
          case mapbox_model.Congestion.HEAVY:
            currentCongestionLevelString = "heavy";
            break;
          case mapbox_model.Congestion.SEVERE:
            currentCongestionLevelString = "severe";
            break;
          case mapbox_model.Congestion.UNKNOWN:
            currentCongestionLevelString = "unknown";
            break;
        }
        congestionList.add(currentCongestionLevelString);

        if (congestionLevelsForLeg[i] != mapbox_model.Congestion.UNKNOWN) {
          trafficIndexesList.add(congestionList.length - 1);
        }

        if ((globalCoordinateIndex + i + 1) <
            fullRouteCoordinatesFromModel.length) {
          final startCoord =
              fullRouteCoordinatesFromModel[globalCoordinateIndex + i];
          final endCoord =
              fullRouteCoordinatesFromModel[globalCoordinateIndex + i + 1];

          trafficSegments.add(
            MapboxFeature(
              geometry: {
                'type': 'LineString',
                'coordinates': [
                  [startCoord.lng, startCoord.lat],
                  [endCoord.lng, endCoord.lat],
                ],
              },
              properties: {
                'mapbox_congestion_level': currentCongestionLevelString,
              },
            ),
          );
        }
      }

      if (currentLeg.steps != null) {
        for (var step in currentLeg.steps!) {
          if (step.geometry != null && step.geometry!.coordinates != null) {
            globalCoordinateIndex += step.geometry!.coordinates!.length;
          }
        }
      }
    }
    // print(
    //   '✅ Finalizado el procesamiento de congestión. Total de segmentos de congestión: ${trafficSegments.length}',
    // );
  }

  Future<void> createCoordinatesSegments({
    required List<mapbox_model.Leg> legList,
  }) async {
    // print(
    //   '🌟 createCoordinatesSegments: Iniciando segmentación de la ruta (Solución de Continuidad)...',
    // );

    routeVisualSegments.clear();

    List<mapbox_model.Step> effectiveRouteSteps = [];
    if (mapboxModel != null &&
        mapboxModel!.routes != null &&
        mapboxModel!.routes!.isNotEmpty &&
        mapboxModel!.routes!.first.legs != null) {
      for (var leg in mapboxModel!.routes!.first.legs!) {
        if (leg.steps != null) {
          effectiveRouteSteps.addAll(leg.steps!);
        }
      }
    } else {
      // print(
      //   '⚠️ createCoordinatesSegments: mapboxModel o sus rutas/legs son nulos/vacíos. Saliendo.',
      // );
      return;
    }

    int globalSegmentCounter = 0;
    mapbox.Position? lastSegmentEndPoint;

    for (int stepIndex = 0;
        stepIndex < effectiveRouteSteps.length;
        stepIndex++) {
      final currentStep = effectiveRouteSteps[stepIndex];

      if (currentStep.geometry == null ||
          currentStep.geometry!.coordinates == null ||
          currentStep.geometry!.coordinates!.isEmpty) {
        continue;
      }

      List<mapbox.Position> stepCoords = currentStep.geometry!.coordinates!
          .map((coordPair) => mapbox.Position(coordPair[0], coordPair[1]))
          .toList();

      int currentStepCoordIndex = 0;

      if (stepIndex > 0) {
        lastSegmentEndPoint = null;
      }

      while (currentStepCoordIndex < stepCoords.length) {
        List<mapbox.Position> segmentCoords = [];

        if (lastSegmentEndPoint != null) {
          segmentCoords.add(lastSegmentEndPoint);
        } else if (currentStepCoordIndex > 0 && stepCoords.isNotEmpty) {
          if (segmentCoords.isEmpty) {
            segmentCoords.add(stepCoords[currentStepCoordIndex - 1]);
          }
        }

        int segmentEndIndex =
            (currentStepCoordIndex + _segmentPointsThreshold - 1);
        if (segmentEndIndex >= stepCoords.length) {
          segmentEndIndex = stepCoords.length - 1;
        }

        for (int i = currentStepCoordIndex; i <= segmentEndIndex; i++) {
          segmentCoords.add(stepCoords[i]);
        }

        if (segmentCoords.isNotEmpty) {
          lastSegmentEndPoint = segmentCoords.last;
        }

        if (segmentCoords.length >= 2) {
          final String segmentId = uuid.v4();
          routeVisualSegments.add(
            RouteSegmentVisual(
              id: segmentId,
              coordinates: segmentCoords,
              isTraversed: false,
              isHidden: false,
              stepIndex: stepIndex,
              segmentNumber: globalSegmentCounter,
            ),
          );
          globalSegmentCounter++;
        } else {
          // print(
          //   '⚠️ Segmento generado con menos de 2 puntos (${segmentCoords.length}), omitido.',
          // );
        }

        currentStepCoordIndex = segmentEndIndex;

        if (currentStepCoordIndex < stepCoords.length - 1) {
          currentStepCoordIndex++;
        } else {
          currentStepCoordIndex = stepCoords.length;
        }
      }
    }

    // print(
    //   '✅ Segmentación de ruta completada. Total de segmentos visuales creados: ${routeVisualSegments.length}',
    // );

    if (routeVisualSegments.length > 1) {
      for (int i = 0; i < routeVisualSegments.length - 1; i++) {
        final currentSegEnd = routeVisualSegments[i].coordinates.last;
        final nextSegStart = routeVisualSegments[i + 1].coordinates.first;

        const double epsilon = 1e-9;

        if ((currentSegEnd.lng - nextSegStart.lng).abs() > epsilon ||
            (currentSegEnd.lat - nextSegStart.lat).abs() > epsilon) {
          // print('❌ Discrepancia de continuidad entre segmento ${i} y ${i + 1}');
          // print(
          //   '   Fin segmento ${i}: (${currentSegEnd.lng}, ${currentSegEnd.lat})',
          // );
          // print(
          //   '   Inicio segmento ${i + 1}: (${nextSegStart.lng}, ${nextSegStart.lat})',
          // );
          // Opcional: throw Exception('Error de continuidad detectado en segmentos GeoJSON');
        }
      }
    }
  }

  Future<List<mapbox.PointAnnotation>> createMarker({
    required String assetPaTh,
    required double lat,
    required double lng,
    required bool isUserMarker,
  }) async {
    if (_mapboxMapController == null || !_isMapReady) {
      _showSnackBar('No se han podido inicializar los marcadores');
      // print(
      //   '❌ Error: _mapboxMapController es nulo o el mapa aún no esta listo. No se pueden crear marcadores.',
      // );
      return []; // Retorna una lista vacía si el controlador no está listo
    }

    final ByteData bytes = await rootBundle.load(assetPaTh);
    final Uint8List list = bytes.buffer.asUint8List();

    pointAnnotationManager ??=
        await _mapboxMapController!.annotations.createPointAnnotationManager();

    List<mapbox.PointAnnotation> createdValidMarkers = [];

    mapbox.PointAnnotationOptions option = mapbox.PointAnnotationOptions(
      geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      image: list, // La imagen cargada
    );

    final List<mapbox.PointAnnotation?> createdMarkersWithNulls =
        await pointAnnotationManager!.createMulti([option]);
    final List<mapbox.PointAnnotation> validMarkersFromMulti =
        createdMarkersWithNulls.whereType<mapbox.PointAnnotation>().toList();

    _destinationMarkers.addAll(validMarkersFromMulti);
    createdValidMarkers.addAll(validMarkersFromMulti);
    // print(
    //   '✅ Marcador adicional creado en Lat: $lat, Lng: $lng. Añadido a _destinationMarkers y devuelto.',
    // );

    return createdValidMarkers;
  }

  Future<void> _setNavigationPerspective({
    required double targetLat,
    required double targetLng,
    double zoom = 15.0, // Zoom por defecto
    double pitch = 50.0, // Inclinación por defecto para vista 3D
    double bearing = 0.0, // 0 grados = Norte arriba por defecto
  }) async {
    if (_mapboxMapController == null) {
      _showSnackBar('No se ha podido cambiar la perspectiva de la navegación');
      // print('Error: MapboxMapController no está inicializado.');
      return;
    }

    final cameraOptions = mapbox.CameraOptions(
      center: mapbox.Point(coordinates: mapbox.Position(targetLng, targetLat)),
      zoom: zoom,
      pitch: pitch,
      bearing: bearing,
    );

    await _mapboxMapController!.flyTo(
      cameraOptions,
      mapbox.MapAnimationOptions(duration: 1000),
    );

    // print(
    //   'Perspectiva del mapa cambiada a: Lat $targetLat, Lng $targetLng, Zoom $zoom, Pitch $pitch, Bearing $bearing',
    // );
  }

  void _startNavigation() async {
    print('🟡 _startNavigation: Iniciando navegación...');

    highestTraversedPointIndex = -1;
    _lastTraversedSegmentIndex = -1;
    _currentRouteStepIndex = 0;

    _hasSpokenInstructionForCurrentStep = false;

    setState(() {
      _isNavigating = true;
    });

    await _getRoute();

    await createCoordinatesSegments(legList: mapboxModel!.routes![0].legs!);

    await _addPolyline();

    if (_currentPosition != null) {
      await createMarker(
        assetPaTh: 'lib/mapbox_kit_navigation/assets/navigation.png',
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
        isUserMarker: true,
      );
      // print(
      //   '📍 Marcador de usuario cambiado a navegación (DESPUÉS de la ruta).',
      // );
    }

    setState(() {
      for (var i = 0; i < selectedPoints.length; i++) {
        createMarker(
          assetPaTh: 'lib/mapbox_kit_navigation/assets/red_marker.png',
          lat: selectedPoints[i].coordinates.lat.toDouble(),
          lng: selectedPoints[i].coordinates.lng.toDouble(),
          isUserMarker: false,
        );
      }
    });

    if (_routeSteps.isNotEmpty) {
      // Correctly access as Map<String, dynamic>
      final Map<String, dynamic> firstStep =
          _routeSteps.first as Map<String, dynamic>; // <-- Corrected casting
      flutterTts.speak(
        firstStep['maneuver']['instruction'],
      ); // <-- Access using [] notation
      _currentRouteStepIndex++;
      _hasSpokenInstructionForCurrentStep = true;
    }

    // _listMapLayers();
    // print('✅ _startNavigation: Navegación iniciada.');
  }

  void _stopNavigation() async {
    // print('🔴 _stopNavigation: Deteniendo navegación...');
    setState(() {
      _isNavigating = false;
      _addedLocations = [];
    });

    await _removePolyline();
    await _removeAllDestinationMarkers();

    routeCoordinates.clear();
    routeSegmentsCoordinates.clear();
    routeVisualSegments.clear();
    features.clear();
    trafficSegments.clear();
    congestionList.clear();
    trafficIndexesList.clear();
    _routeSteps.clear();
    _currentRouteStepIndex = 0;
    _hasSpokenInstructionForCurrentStep = false;
    lastConsumedSegmentIndex = -1;
    _lastTraversedSegmentIndex = -1;
    highestTraversedPointIndex = -1;
    selectedPoints = [];

    // print('✅ _stopNavigation: Navegación detenida y ruta eliminada.');
  }

  void clearRouteRlatedState() {
    routeCoordinates.clear();
    routeSegmentsCoordinates.clear(); //
    _routeSteps.clear();
    routeVisualSegments.clear();
    trafficSegments.clear();
    highestTraversedPointIndex = -1;
    _currentRouteStepIndex = 0;
    _isNavigating = false;
    _hasSpokenInstructionForCurrentStep = false;
    _lastTraversedSegmentIndex = -1;
    lastConsumedSegmentIndex = -1;

    selectedPoints.clear();
    _addedLocations.clear();
    _removeAllDestinationMarkers();
  }

  Future<void> _removeAllDestinationMarkers() async {
    if (pointAnnotationManager == null) {
      // print('ℹ️ _removeAllDestinationMarkers: pointAnnotationManager es nulo.');
      return;
    }

    if (_destinationMarkers.isNotEmpty) {
      try {
        for (var marker in _destinationMarkers) {
          await pointAnnotationManager!.delete(marker);
          // print('DEBUG: Marcador ${marker.id} eliminado.');
        }

        _destinationMarkers.clear(); // Limpiar la lista después de eliminarlos
        // print('✅ Todos los marcadores de destino eliminados exitosamente.');
      } catch (e) {
        // print('❌ Error al eliminar marcadores de destino: $e');
      }
    } else {
      // print('ℹ️ No hay marcadores de destino para eliminar.');
    }
  }

  String _toHexColorString(int argbValue) {
    return '#${(argbValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Future<void> _addPolyline() async {
    if (_mapboxMapController == null) return;

    // print(
    //   '🌟 _addRouteToMap: Añadiendo la ruta base de segmentos (para borrado)...',
    // );

    if (await _mapboxMapController!.style.styleLayerExists(
      'route-base-segments-layer',
    )) {
      await _mapboxMapController!.style.removeStyleLayer(
        'route-base-segments-layer',
      );
    }
    if (await _mapboxMapController!.style.styleSourceExists(
      'route-base-segments-source',
    )) {
      await _mapboxMapController!.style.removeStyleSource(
        'route-base-segments-source',
      );
    }

    if (await _mapboxMapController!.style.styleLayerExists(
      'route-traffic-layer',
    )) {
      await _mapboxMapController!.style.removeStyleLayer('route-traffic-layer');
    }
    if (await _mapboxMapController!.style.styleSourceExists(
      'route-traffic-source',
    )) {
      await _mapboxMapController!.style.removeStyleSource(
        'route-traffic-source',
      );
    }

    _polylineAnnotationManager ??= await _mapboxMapController!.annotations
        .createPolylineAnnotationManager();

    if (_traversedPolyline != null) {
      await _polylineAnnotationManager!.delete(_traversedPolyline!);
      _traversedPolyline = null;
    }

    List<mapbox.Feature> baseSegmentFeatures = [];
    for (var visualSegment in routeVisualSegments) {
      baseSegmentFeatures.add(
        mapbox.Feature(
          id: visualSegment.id,
          geometry: mapbox.LineString(coordinates: visualSegment.coordinates),
          properties: {
            'segment_number': visualSegment.segmentNumber,
            'is_traversed': visualSegment.isTraversed,
            'is_hidden': visualSegment.isHidden,
          },
        ),
      );
    }

    if (baseSegmentFeatures.isNotEmpty) {
      final baseSegmentFeatureCollection = mapbox.FeatureCollection(
        features: baseSegmentFeatures,
      );
      await _mapboxMapController!.style.addSource(
        mapbox.GeoJsonSource(
          id: 'route-base-segments-source',
          data: jsonEncode(baseSegmentFeatureCollection.toJson()),
        ),
      );

      await _mapboxMapController!.style.addLayer(
        mapbox.LineLayer(
          id: 'route-base-segments-layer',
          sourceId: 'route-base-segments-source',
          lineWidth: 5.0,
          lineJoin: mapbox.LineJoin.ROUND,
          lineCap: mapbox.LineCap.ROUND,
          lineColorExpression: [
            _toHexColorString(Colors.blue.toARGB32()),
            // 'case',
            // [
            //   '==',
            //   [
            //     '%',
            //     ['get', 'segment_number'],
            //     2,
            //   ],
            //   0,
            // ], // Si es par
            // _toHexColorString(Colors.purple.toARGB32()),
            // _toHexColorString(
            //   Colors.orange.toARGB32(),
            // ), // Si es impar (fallback)
          ],
          filter: [
            '==', // Opera el filtro como 'si esta propiedad es igual a este valor'
            ['get', 'is_hidden'],
            false,
          ],
        ),
      );
      // print('DEBUG: Capa route-base-segments-layer AÑADIDA.');
    }

    if (mounted) {
      setState(() {});
    }

    // print('✅ _addRouteToMap: Ruta base de segmentos añadida exitosamente.');
  }

  // Future<void> _listMapLayers() async {
  //   if (_mapboxMapController == null) return;

  //   try {
  //     final allLayerIds = await _mapboxMapController!.style.getStyleLayers();

  //     print('✅ Capas actuales en el mapa (IDs):');
  //     for (var layerId in allLayerIds) {
  //       print('  - ID: ${layerId!.id}');
  //     }
  //   } catch (e) {
  //     print('❌ Error al listar las capas del mapa: $e');
  //   }
  // }

  Future<void> _removePolyline() async {
    if (_mapboxMapController == null) return;

    // print('🔴 _removePolyline: Iniciando eliminación de capas de ruta.');

    // Eliminar la capa y fuente de SEGMENTOS BASE (morado/naranja)
    if (await _mapboxMapController!.style.styleLayerExists(
      'route-base-segments-layer',
    )) {
      await _mapboxMapController!.style.removeStyleLayer(
        'route-base-segments-layer',
      );
      // print('✅ Capa de segmentos base (route-base-segments-layer) eliminada.');
    }
    if (await _mapboxMapController!.style.styleSourceExists(
      'route-base-segments-source',
    )) {
      await _mapboxMapController!.style.removeStyleSource(
        'route-base-segments-source',
      );
      // print(
      //   '✅ Fuente de segmentos base (route-base-segments-source) eliminada.',
      // );
    }

    // Eliminar cualquier capa de tráfico si existía y también quieres limpiarla
    if (await _mapboxMapController!.style.styleLayerExists(
      'route-traffic-layer',
    )) {
      await _mapboxMapController!.style.removeStyleLayer('route-traffic-layer');
      // print('✅ Capa de tráfico (route-traffic-layer) eliminada.');
    }
    if (await _mapboxMapController!.style.styleSourceExists(
      'route-traffic-source',
    )) {
      await _mapboxMapController!.style.removeStyleSource(
        'route-traffic-source',
      );
      // print('✅ Fuente de tráfico (route-traffic-source) eliminada.');
    }

    if (_polylineAnnotationManager != null) {
      if (_traversedPolyline != null) {
        try {
          await _polylineAnnotationManager!.delete(_traversedPolyline!);
          _traversedPolyline = null;
          // print('✅ _traversedPolyline (línea azul anterior) eliminada.');
        } catch (e) {
          // print('⚠️ Advertencia: Error al eliminar _traversedPolyline: $e');
        }
      }
      // Si _unTraversedPolyline existe (aunque ya no lo usamos en esta estrategia), también limpiarlo
      if (_unTraversedPolyline != null) {
        try {
          await _polylineAnnotationManager!.delete(_unTraversedPolyline!);
          _unTraversedPolyline = null;
          // print('✅ _unTraversedPolyline (línea verde anterior) eliminada.');
        } catch (e) {
          // print('⚠️ Advertencia: Error al eliminar _unTraversedPolyline: $e');
        }
      }
    }

    // print('✅ _removePolyline: Limpieza de capas de ruta completada.');
  }

  // Métodos para manejar el zoom
  Future<void> _zoomIn() async {
    if (_mapboxMapController != null) {
      mapbox.CameraState cs = await _mapboxMapController!.getCameraState();
      mapbox.CameraOptions co = mapbox.CameraOptions(
        center: cs.center,
        zoom: cs.zoom + 1,
        bearing: cs.bearing,
        pitch: cs.pitch,
      );
      _mapboxMapController!.easeTo(
        co,
        mapbox.MapAnimationOptions(duration: 200, startDelay: 0),
      );
    }
  }

  Future<void> _zoomOut() async {
    if (_mapboxMapController != null) {
      mapbox.CameraState cs = await _mapboxMapController!.getCameraState();

      if (cs.zoom > 0) {
        mapbox.CameraOptions co = mapbox.CameraOptions(
          center: cs.center,
          zoom: cs.zoom - 1,
          bearing: cs.bearing,
          pitch: cs.pitch,
        );
        _mapboxMapController!.easeTo(
          co,
          mapbox.MapAnimationOptions(duration: 200, startDelay: 0),
        );
      }
    }
  }

  // --- Funciones para la búsqueda ---

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.isNotEmpty) {
        _getPlaceSuggestions(_searchController.text);
      } else {
        setState(() {
          _suggestions = [];
        });
      }
    });
  }

  Future<void> _getPlaceSuggestions(String pattern) async {
    // print('🌟 get places');
    // if (pattern.isEmpty) {
    //   // if (_searchController.text.isEmpty) {
    //   return [];
    // }

    final String accessToken = widget.mapboxAccessToken;

    final url = Uri.parse(
      // 'https://api.mapbox.com/geocoding/v5/mapbox.places/$pattern.json?access_token=$accessToken&language=es&autocomplete=true',
      'https://api.mapbox.com/search/searchbox/v1/forward?q=$pattern&&proximity=${_currentPosition!.longitude},${_currentPosition!.latitude}&access_token=$accessToken',
      // 'https://api.mapbox.com/search/searchbox/v1/suggest?q=$pattern&proximity=${_currentPosition!.longitude},${_currentPosition!.latitude}&access_token=$accessToken',
    );

    // print('💖 response $url');

    try {
      final response = await http.get(url);
      // print('💖 response ${response.body}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        // final properties = data['properties'];
        setState(() {
          _suggestions = features.map((feature) {
            return {
              'name': feature['properties']['name'],
              'coordinates': feature['geometry']
                  ['coordinates'], // [longitude, latitude]
            };
          }).toList();
        });
      } else {
        // print('Error en la API de Mapbox Geocoding: ${response.statusCode}');
        setState(() {
          _suggestions = [];
        });
        // return [];
      }
    } catch (e) {
      // print('Error al obtener sugerencias de lugares: $e');
      setState(() {
        _suggestions = [];
      });
      // return [];
    }
  }

  void _onSuggestionSelected(Map<String, dynamic> suggestion) async {
    final String name = suggestion['name'];
    // [longitude, latitude]
    final List<dynamic> coords = suggestion['coordinates'];
    // Point.fromLngLat espera (longitude, latitude)
    final mapbox.Point point = mapbox.Point(
      coordinates: mapbox.Position(coords[0], coords[1]),
    );

    selectedPoints.add(
      mapbox.Point(
        coordinates: mapbox.Position(
          point.coordinates.lng,
          point.coordinates.lat,
        ),
      ),
    );

    final createdMarkers = await createMarker(
      assetPaTh: 'lib/mapbox_kit_navigation/assets/red_marker.png',
      lat: point.coordinates.lat.toDouble(),
      lng: point.coordinates.lng.toDouble(),
      isUserMarker: false,
    );

    mapbox.PointAnnotation? markerReference;
    if (createdMarkers.isNotEmpty) {
      markerReference = createdMarkers.first;
    }

    setState(() {
      _addedLocations.add({
        'name': name,
        'point': point,
        'marker': markerReference,
      });
    });

    _searchController.text = name;

    _mapboxMapController?.setCamera(
      mapbox.CameraOptions(center: point, zoom: 14.0),
    );

    FocusScope.of(context).unfocus();
    _searchController.clear();
  }

  Future<void> _checkRouteProgress() async {
    if (!_isNavigating || _currentPosition == null) {
      return;
    }

    // Lógica para las instrucciones de voz (basada en _routeSteps)
    if (_currentRouteStepIndex < _routeSteps.length) {
      // print('🔴🔴🔴 for _if currentroutestepindex');

      final Map<String, dynamic> currentStep =
          _routeSteps[_currentRouteStepIndex]
              as Map<String, dynamic>; // <-- Corrected casting
      final instruction = currentStep['maneuver']['instruction'] as String;
      final double maneuverLat =
          (currentStep['maneuver']['location'][1] as num).toDouble();
      final double maneuverLng =
          (currentStep['maneuver']['location'][0] as num).toDouble();

      final double distanceToManeuver = geo.Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        maneuverLat,
        maneuverLng,
      );
      // print('✅ Distance to mauneaver $distanceToManeuver');

      if (distanceToManeuver < 100 && !_hasSpokenInstructionForCurrentStep) {
        print('🔊 Instrucción de voz: $instruction');
        flutterTts.speak(instruction);
        _hasSpokenInstructionForCurrentStep = true;
      }

      if (distanceToManeuver < 15 && _hasSpokenInstructionForCurrentStep) {
        _currentRouteStepIndex++;

        _hasSpokenInstructionForCurrentStep = false;
      }
    } else {
      if (_isNavigating) {
        flutterTts.speak('Has llegado a tu destino.');
        _stopNavigation();
        return;
      }
    }

    bool shouldUpdateVisuals = false;
    for (int i = _lastTraversedSegmentIndex + 1;
        i < routeVisualSegments.length;
        i++) {
      // print('🟡🟡🟡 for lastraversed');
      // print('🟡🟡🟡 for i $i');
      // print('🟡🟡🟡 for lasttraversedsegmentindex $_lastTraversedSegmentIndex');
      final segment = routeVisualSegments[i];

      if (segment.coordinates.length < 2) continue;

      // Último punto del segmento
      final segmentEndCoord = segment.coordinates.last;

      final double distanceToSegmentEnd = geo.Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        segmentEndCoord.lat.toDouble(),
        segmentEndCoord.lng.toDouble(),
      );

      // print('✅ distance segment to end $distanceToSegmentEnd');
      if (distanceToSegmentEnd < 20) {
        if (!segment.isTraversed) {
          segment.isTraversed = true;
          segment.isHidden = true;
          _lastTraversedSegmentIndex = i;
          shouldUpdateVisuals = true;
          // print(
          //   '✅ Segmento ${segment.id} marcado como recorrido y oculto. Nuevo _lastTraversedSegmentIndex: $_lastTraversedSegmentIndex. Activando actualización visual.',
          // );
        }

        // print(
        //   '✅ Segmento ${segment.id} marcado como recorrido y oculto. Nuevo _lastTraversedSegmentIndex: $_lastTraversedSegmentIndex. Activando actualización visual.',
        // );
      } else {
        // print(
        //   'DEBUG: Segmento $i no alcanzado. Distancia: ${distanceToSegmentEnd.toStringAsFixed(2)}m',
        // );
        // Si el usuario no ha alcanzado el final de este segmento, no hay necesidad de revisar los siguientes
        break;
      }
    }

    if (shouldUpdateVisuals) {
      // print(
      //   'DEBUG: _checkRouteProgress: Un segmento fue recorrido, llamando a _updateRouteVisuals().',
      // );
      await _updateRouteVisuals();
    } else {
      // print(
      //   'DEBUG: _checkRouteProgress: No hay nuevos segmentos recorridos en esta actualización.',
      // );
    }
  }

  Future<void> _updateRouteVisuals() async {
    // print(
    //   'DEBUG: === Entrando a _updateRouteVisuals() (BORRADO POR ELIMINACIÓN) ===',
    // );

    if (_mapboxMapController == null) {
      // print('⚠️ _updateRouteVisuals: _mapboxMapController es NULO. Saliendo.');
      return;
    }
    if (routeVisualSegments.isEmpty) {
      // print(
      //   '⚠️ _updateRouteVisuals: routeVisualSegments está VACÍA. Saliendo.',
      // );
      return;
    }

    List<mapbox.Feature> remainingVisibleFeatures = [];
    String sourceIdToUpdate = 'route-base-segments-source';
    String layerIdToUpdate = 'route-base-segments-layer';

    for (int i = 0; i < routeVisualSegments.length; i++) {
      final visualSegment = routeVisualSegments[i];
      if (!visualSegment.isHidden) {
        remainingVisibleFeatures.add(
          mapbox.Feature(
            id: visualSegment.id,
            geometry: mapbox.LineString(coordinates: visualSegment.coordinates),
            properties: {
              'segment_number': visualSegment.segmentNumber,
              'is_traversed': visualSegment.isTraversed,
              'is_hidden': visualSegment.isHidden,
            },
          ),
        );
      }
    }

    final updatedFeatureCollection = mapbox.FeatureCollection(
      features: remainingVisibleFeatures,
    );
    final updatedGeoJsonString = jsonEncode(updatedFeatureCollection.toJson());

    // print(
    //   'DEBUG: GeoJSON ENVIADO A MAPBOX para actualización (solo visibles):',
    // );
    // print(
    //   '🆘 DEBUG: ${updatedGeoJsonString.length > 500 ? updatedGeoJsonString.substring(0, 500) + '...' : updatedGeoJsonString}',
    // );
    if (remainingVisibleFeatures.isNotEmpty) {
      // print('🆘 DEBUG: Ejemplo de Feature *VISIBLE* (primer segmento):');
      // print('🆘 DEBUG: ${jsonEncode(remainingVisibleFeatures[0].toJson())}');
    } else {
      // print(
      //   '🆘 DEBUG: remainingVisibleFeatures está vacía. Toda la ruta debería haber desaparecido.',
      // );
    }

    // Paso 2: Remover y Añadir la Fuente y la Capa (como antes)
    try {
      bool layerExists = await _mapboxMapController!.style.styleLayerExists(
        layerIdToUpdate,
      );
      bool sourceExists = await _mapboxMapController!.style.styleSourceExists(
        sourceIdToUpdate,
      );
      // print(
      //   'DEBUG: _updateRouteVisuals: Capa "$layerIdToUpdate" existe: $layerExists. Fuente "$sourceIdToUpdate" existe: $sourceExists.',
      // );

      if (layerExists) {
        await _mapboxMapController!.style.removeStyleLayer(layerIdToUpdate);
        // print('✅ Capa removida: $layerIdToUpdate');
      }
      if (sourceExists) {
        await _mapboxMapController!.style.removeStyleSource(sourceIdToUpdate);
        // print('✅ Fuente removida: $sourceIdToUpdate');
      }

      await Future.delayed(Duration(milliseconds: 50));

      await _mapboxMapController!.style.addSource(
        mapbox.GeoJsonSource(id: sourceIdToUpdate, data: updatedGeoJsonString),
      );
      // print('✅ Fuente añadida de nuevo: $sourceIdToUpdate');

      await _mapboxMapController!.style.addLayer(
        mapbox.LineLayer(
          id: layerIdToUpdate,
          sourceId: sourceIdToUpdate,
          lineWidth: 5.0,
          lineJoin: mapbox.LineJoin.ROUND,
          lineCap: mapbox.LineCap.ROUND,
          lineColorExpression: [
            _toHexColorString(Colors.blue.toARGB32()),
            // 'case',
            // [
            //   '==',
            //   [
            //     '%',
            //     ['get', 'segment_number'],
            //     2,
            //   ],
            //   0,
            // ],
            // _toHexColorString(Colors.purple.toARGB32()),
            // _toHexColorString(Colors.orange.toARGB32()),
          ],
        ),
      );
      // print('✅ Capa añadida de nuevo: $layerIdToUpdate');
    } catch (e) {
      _showSnackBar('No se pudo actualizar la ruta, ${e.toString()}');
      // print(

      //   '❌ ERROR en _updateRouteVisuals al remover/añadir fuente o capa: $e',
      // );
      // print('Stacktrace: ${e.toString()}');
    }
    // print('DEBUG: === Saliendo de _updateRouteVisuals() ===');
  }

  Future<double> calculateDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) async {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 1000 * 12742 * asin(sqrt(a));
  }

  Future<void> _removeSingleDestinationMarker(
    mapbox.PointAnnotation markerToRemove,
    int index,
  ) async {
    if (pointAnnotationManager == null) {
      _showSnackBar('Ocurrió un error al remover destino');
      // print(
      //   'ℹ️ _removeSingleDestinationMarker: pointAnnotationManager es nulo.',
      // );
      return;
    }

    // print(
    //   '🔴 _removeSingleDestinationMarker: Eliminando marcador de destino individual: ${markerToRemove.id}',
    // );

    try {
      await pointAnnotationManager!.delete(markerToRemove); // Eliminar del mapa
      _destinationMarkers.remove(markerToRemove);
      setState(() {
        _addedLocations.removeAt(index);
        selectedPoints.removeAt(index);
      });

      // print(
      //   '✅ Marcador ${markerToRemove.id} y lugar asociado eliminados exitosamente.',
      // );
    } catch (e) {
      _showSnackBar('Ocurrió un error al eliminar el marcador de este lugar');
      // print('❌ Error al eliminar marcador individual: $e');
    }
  }
}
