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
import 'package:mapbox_kit_navigation/src/models/mapbox_feature.dart';
import 'package:mapbox_kit_navigation/mapbox_navigation_kit.dart';

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

  final mapbox.Point otherPoint = mapbox.Point(
    coordinates: mapbox.Position(-101.6808, 21.1253),
  ); // Recuerda: Longitud, Latitud// Ejemplo: Catedral de León

  // List<List<double>> _routeCoordinates = [];
  List<dynamic> mapboxGeometry = [];
  //to use static places
  // primero va lng
  List<mapbox.Point> deliverPoints = [
    //dilo maps
    // mapbox.Point(coordinates: mapbox.Position(-101.6740238, 21.1160227)),
    //dilo mapbox
    mapbox.Point(coordinates: mapbox.Position(-101.67142131, 21.11600757)),
    //forum maps
    // mapbox.Point(coordinates: mapbox.Position(-101.6630901, 21.115909)),
    //forum mapbox
    mapbox.Point(coordinates: mapbox.Position(-101.66048546, 21.11595034)),
    //poliforum maps
    // mapbox.Point(coordinates: mapbox.Position(-101.6631432, 21.1159041)),
    //poliforum mapbox
    mapbox.Point(coordinates: mapbox.Position(-101.65460351, 21.1141399)),
    //vity plaza mapbox
    mapbox.Point(
      coordinates: mapbox.Position(-101.68285433651064, 21.16990091870788),
    ),
  ];

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
  mapbox.PolylineAnnotation? _routePolyline;

  int currentIndexStep = 0;

  late final featureCollection;
  List<mapbox.Feature> features = [];
  int indexRemoveSedmentPolyline = 0;

  // Esto podría ser un Map para asociar un ID de segmento de ruta con el ID de la Feature en el mapa.
  Map<String, String> _segmentToFeatureIdMap = {};

  List<String> _drawnSegmentIds = [];
  // Cantidad de segmentos a dibujar
  final int _segmentPointsThreshold = 5;

  int _lastConsumedSegmentIndex = -1;
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
  int _highestTraversedPointIndex = -1;

  // Asegúrate de inicializar Uuid
  final Uuid uuid = Uuid();

  // Para almacenar los marcadores de destino
  List<mapbox.PointAnnotation> _destinationMarkers = [];

  String _userSourceId = 'user-location-source';
  String _userLayerId = 'user-location-layer';

  @override
  void initState() {
    super.initState();
    mapbox.MapboxOptions.setAccessToken(widget.mapboxAccessToken);
    // _requestLocationPermission();
    // WidgetsBinding.instance.addPostFrameCallback((timestamp) async {
    //   await _getCurrentLocation();
    //   // await createMarker(
    //   //   assetPaTh: 'assets/user_marker.png',
    //   //   lat: _currentPosition!.latitude,
    //   //   lng: _currentPosition!.longitude,
    //   // );
    // });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Navegación Mapbox')),
      body: Stack(
        children: [
          _currentPosition == null
              ? const Center(
                child: CircularProgressIndicator(),
              ) // Cambia color para que destaque
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
                  // print('DEBUG: onMapCreated - _mapboxMapController asignado.');

                  // Intentamos crear el PointAnnotationManager aquí, una vez que el mapa esté listo.
                  pointAnnotationManager ??=
                      await _mapboxMapController!.annotations
                          .createPointAnnotationManager();
                  print('DEBUG: PointAnnotationManager inicializado.');

                  // Si _currentPosition ya está disponible, creamos el marcador de usuario
                  // if (_currentPosition != null && userMarker == null) {
                  //   await createMarker(
                  //     assetPaTh: 'assets/user_marker.png',
                  //     lat: _currentPosition!.latitude,
                  //     lng: _currentPosition!.longitude,
                  //     isUserMarker: true,
                  //   );
                  //   print('DEBUG: Marcador de usuario creado en onMapCreated.');
                  // }

                  // Una vez que el controlador y los elementos básicos están listos,
                  // marcamos el mapa como listo para mostrarse
                  setState(() {
                    _isMapReady = true;
                  });
                  await _requestLocationPermission();
                },
                onStyleLoadedListener: (style) async {},
              ),
          // Caja de búsqueda (TextField con sugerencias)
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
                          suffixIcon:
                              _searchController.text.isNotEmpty
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
                            maxHeight: MediaQuery.of(context).size.height * 0.3,
                          ),
                          child: ListView.builder(
                            shrinkWrap:
                                true, // Importante para que ListView.builder no ocupe todo el espacio disponible
                            itemCount: _suggestions.length,
                            itemBuilder: (context, index) {
                              final suggestion = _suggestions[index];
                              return ListTile(
                                title: Text(suggestion['name']),
                                onTap: () {
                                  print(
                                    'suggestion 💔 ${_searchController.text}',
                                  );
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
                                          width:
                                              MediaQuery.of(
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
                                                location['marker']
                                                    as mapbox.PointAnnotation?;
                                            if (markerReference != null) {
                                              _removeSingleDestinationMarker(
                                                markerReference,
                                                index,
                                              );
                                            } else {
                                              // Si por alguna razón la referencia al marcador no está,
                                              // aún puedes intentar remover por índice (menos seguro)
                                              setState(() {
                                                _addedLocations.removeAt(index);
                                                selectedPoints.removeAt(index);
                                              });
                                              print(
                                                '⚠️ No se encontró referencia al marcador para eliminarlo del mapa.',
                                              );
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
                                  Divider(color: Colors.grey, thickness: .5),
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
                  heroTag:
                      "zoomInBtn", // Añade un heroTag único para evitar errores
                  onPressed: _zoomIn,
                  mini: true,
                  child: const Icon(Icons.add),
                ),
                // const SizedBox(height: 5),
                FloatingActionButton(
                  heroTag: "zoomOutBtn", // Añade un heroTag único
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
    );
  }

  //all functional methods
  Future<void> _initTextToSpeech() async {
    await flutterTts.setLanguage('es-MX');
    await flutterTts.setSpeechRate(0.4);
  }

  Future<void> _requestLocationPermission() async {
    print('🌟🌟🌟🌟 request epermision');
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      await _getCurrentLocation();
    } else {
      print('Permiso de ubicación denegado.');
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
    print('㊗️ Iniciando _getCurrentLocation...');
    try {
      _mapboxMapController?.location.updateSettings(
        mapbox.LocationComponentSettings(enabled: true),
      );
      const geo.LocationSettings locationSettings = geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high, // Mayor precisión
        distanceFilter: 5,
        // Actualizar solo si la posición cambia más de 5 metros
      );

      // 1. Obtener la posición inicial actual del usuario
      geo.Position initialPosition = await geo.Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );

      // 2. Asignar la posición inicial a _currentPosition
      _currentPosition =
          initialPosition; // ¡Descomentado y asignado correctamente!
      print(
        '🌟 Posición inicial obtenida: Lat ${_currentPosition!.latitude}, Lng ${_currentPosition!.longitude}',
      );

      // **** CAMBIO CLAVE: Esperar a que el mapa esté listo antes de operar ****
      // Usamos `await Future.doWhile` para esperar hasta que `_isMapReady` sea true
      await Future.doWhile(() async {
        await Future.delayed(
          const Duration(milliseconds: 100),
        ); // Pequeña espera
        return !_isMapReady; // Continuar esperando si no está listo
      });
      print(
        'DEBUG: _getCurrentLocation: _isMapReady es TRUE. Continuando con operaciones del mapa.',
      );

      // Crear/Actualizar la capa del usuario inmediatamente después de que el mapa esté listo
      await _updateUserLocationLayer(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _currentPosition!.heading,
      );
      print('📍 Marcador de usuario inicial (SymbolLayer) creado.');

      // 3. Crear el marcador inicial del usuario (no navegando)
      // Se usa 'assets/user_marker.png' por defecto
      await createMarker(
        assetPaTh: 'assets/user_marker.png', // Marcador por defecto
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
        isUserMarker: true,
      );
      print('📍 Marcador de usuario inicial creado.');

      // 4. Mover la cámara a la posición inicial
      if (_mapboxMapController != null) {
        _updateCameraPosition(
          mapbox.Position(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
        );
        print('🗺️ Cámara movida a la posición inicial.');
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
          final String markerAsset =
              _isNavigating
                  ? 'assets/navigation.png' // Si navegando, usa este asset
                  : 'assets/user_marker.png'; // Si no navegando, usa este asset

          // Actualizar el marcador del usuario en cada cambio de posición
          // Asegurarse de que userMarker no sea null antes de intentar actualizarlo
          if (pointAnnotationManager != null && userMarker != null) {
            final updatedMarkerOptions = mapbox.PointAnnotationOptions(
              geometry: mapbox.Point(
                coordinates: mapbox.Position(
                  _currentPosition!.longitude,
                  _currentPosition!.latitude,
                ),
              ),
              // Cargar la imagen del asset para la actualización
              image: (await rootBundle.load(markerAsset)).buffer.asUint8List(),
            );
            // Eliminar el marcador viejo y crear uno nuevo con la imagen correcta
            // Esto es más robusto si la imagen necesita cambiar, ya que update
            // a veces no cambia la imagen del asset directamente.
            await pointAnnotationManager!.delete(userMarker!);
            userMarker = await pointAnnotationManager!.create(
              updatedMarkerOptions,
            );
            print('📍 Marcador de usuario actualizado en stream.');
          } else {
            // Si el marcador no existe (esto no debería pasar si se inicializa correctamente)
            await createMarker(
              assetPaTh: markerAsset,
              lat: _currentPosition!.latitude,
              lng: _currentPosition!.longitude,
              isUserMarker: true,
            );
            print(
              '📍 Marcador de usuario creado en stream (fallo de inicialización anterior).',
            );
          }

          // Lógica de navegación (perspectiva y progreso)
          if (_isNavigating) {
            _setNavigationPerspective(
              targetLat: _currentPosition!.latitude,
              targetLng: _currentPosition!.longitude,
              bearing:
                  _currentPosition!.heading, // Ajustar el rumbo de la cámara
            );
            _checkRouteProgress(); //
          }

          // Llamar setState para que la UI de Flutter refleje cualquier cambio de estado
          // (Aunque las actualizaciones del marcador se hacen directamente al MapboxMapController,
          // setState es bueno para otros cambios de UI dependientes de _currentPosition o _isNavigating)
          setState(() {});
        },
        onError: (error) {
          print('Error al obtener la ubicación en stream: $error');
        },
      );

      // No se necesita setState aquí al final del método si todo se maneja en el stream
      // y la inicialización.
      // setState(() {}); // Eliminamos este setState redundante y potencialmente problemático
    } catch (e) {
      print('❌ Error al obtener la ubicación (try/catch principal): $e');
    }
  }

  Future<void> _updateUserLocationLayer(
    double lat,
    double lng,
    double bearing,
  ) async {
    if (_mapboxMapController == null) return;

    final String assetPath =
        _isNavigating
            ? 'assets/navigation_marker.png' // Nuevo marcador para navegación
            : 'assets/user_marker.png'; // Marcador normal

    // Cargar el asset de la imagen
    final ByteData bytes = await rootBundle.load(assetPath);
    final Uint8List list = bytes.buffer.asUint8List();

    // Redimensionar la imagen a un tamaño razonable para SymbolLayer (ej. 48x48 px)
    // Puedes usar tu función _resizeAssetImage si la implementaste, o simplemente
    // asegura que tus assets ya están en el tamaño deseado.
    // Pero la MEJOR FORMA es redimensionar los assets fuera de Flutter.

    // El ID de la imagen en el estilo.
    final String imageId =
        _isNavigating ? 'assets/navigation.png' : 'assets/user_marker.png';

    await createMarker(
      assetPaTh: 'assets/user_marker.png',
      lat: _currentPosition!.latitude,
      lng: _currentPosition!.longitude,
      isUserMarker: true,
    );

    // Añadir/Actualizar la imagen en el estilo del mapa
    // try-catch para manejar el caso de que la imagen ya exista, ya que `addImage`
    // lanzará un error si el ID de imagen ya está en uso.
    // try {
    //   await _mapboxMapController!.style.addImage(imageId, list);
    //   print('✅ Imagen "$imageId" añadida/actualizada al estilo del mapa.');
    // } catch (e) {
    //   // Si la imagen ya existe, simplemente la ignora y continúa.
    //   print('ℹ️ Imagen "$imageId" ya existe en el estilo del mapa. Continuar.');
    // }

    // Crea la Feature GeoJSON para el punto del usuario
    final userFeature = mapbox.Feature(
      id: 'user-location-feature', // ID único para la Feature del usuario
      geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      properties: {
        'bearing': bearing, // Pasar el rumbo para la rotación del icono
        'asset_path':
            assetPath, // También útil para depuración o si se usa en expresiones
      },
    );

    final userGeoJson = jsonEncode(
      mapbox.FeatureCollection(features: [userFeature]).toJson(),
    );

    // Estrategia: Eliminar y Añadir Fuente/Capa para la ubicación del usuario
    // Esto asegura que la capa del usuario siempre esté encima de todas las demás si se añade al final.
    // Y es la estrategia más robusta dada tu versión del SDK.
    bool userLayerExists = await _mapboxMapController!.style.styleLayerExists(
      _userLayerId,
    );
    bool userSourceExists = await _mapboxMapController!.style.styleSourceExists(
      _userSourceId,
    );

    if (userLayerExists) {
      await _mapboxMapController!.style.removeStyleLayer(_userLayerId);
      print('🗑️ Capa de usuario removida: $_userLayerId');
    }
    if (userSourceExists) {
      await _mapboxMapController!.style.removeStyleSource(_userSourceId);
      print('🗑️ Fuente de usuario removida: $_userSourceId');
    }

    // Pequeña pausa para dar tiempo al SDK nativo a procesar la eliminación
    await Future.delayed(Duration(milliseconds: 10));

    await _mapboxMapController!.style.addSource(
      mapbox.GeoJsonSource(id: _userSourceId, data: userGeoJson),
    );
    print('➕ Fuente de usuario añadida: $_userSourceId');

    await _mapboxMapController!.style.addLayer(
      mapbox.SymbolLayer(
        id: _userLayerId,
        sourceId: _userSourceId,
        // Usa el ID de la imagen que añadimos al estilo
        iconImage: imageId,
        // Tamaño original del icono (se recomienda que el asset ya tenga el tamaño deseado)
        iconSize: 1.0,
        iconAllowOverlap: true, // Permitir que el icono se superponga con otros
        // Ignorar la colocación para que siempre se vea
        iconIgnorePlacement: true,
        // Rotar el icono en relación con el mapa
        iconRotationAlignment: mapbox.IconRotationAlignment.MAP,
        // iconRotate: [
        //   'get',
        //   'bearing',
        // ], // Rotar el icono según la propiedad 'bearing' del GeoJSON
      ),
    );
    print('✅ Capa de ubicación de usuario actualizada con asset: $assetPath');
  }

  void _updateCameraPosition(mapbox.Position latLng) {
    _mapboxMapController?.flyTo(
      // Usar flyTo en lugar de animateCamera
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(latLng.lng, latLng.lat),
        ),
        zoom: 15.0,
      ),

      mapbox.MapAnimationOptions(
        duration: 1000,
      ), // Puedes ajustar la duración de la animación
    );
  }

  Future<void> _getRoute() async {
    print('🌟 get route');
    final String baseUrl =
        'https://api.mapbox.com/directions/v5/mapbox/driving';

    List<mapbox.Point> pointsForDirectionsApi = [];

    // Decidir qué puntos usar para la petición a la API de Directions
    if (!widget.showSearchBar &&
        widget.routeCoordinatesList != null &&
        widget.routeCoordinatesList!.isNotEmpty) {
      // Si no hay barra de búsqueda, usamos la lista de coordenadas obligatoria.
      // Convertir List<List<double>> a List<mapbox.Point>
      pointsForDirectionsApi.addAll(
        widget.routeCoordinatesList!
            .map(
              (coords) => mapbox.Point(
                coordinates: mapbox.Position(coords[0], coords[1]),
              ),
            )
            .toList(),
      );
      print(
        'DEBUG: Usando puntos de ruta proporcionados al constructor de la biblioteca.',
      );
    } else if (widget.showSearchBar && selectedPoints.isNotEmpty) {
      // Si hay barra de búsqueda, usamos los puntos seleccionados por el usuario.
      pointsForDirectionsApi.addAll(selectedPoints);
      print('DEBUG: Usando puntos de ruta seleccionados por el usuario.');
    } else {
      // Caso de error: no hay puntos ni predefinidos ni seleccionados
      print(
        '🖐️ Advertencia: No hay puntos de ruta para calcular. No se pudo iniciar la navegación.',
      );
      _showSnackBar(
        'No hay puntos de ruta válidos. Por favor, selecciona o proporciona puntos.',
      );
      _removePolyline();
      _highestTraversedPointIndex = -1;
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
      print(
        '🖐️ Advertencia: Necesitas seleccionar al menos un lugar para calcular una ruta.',
      );
      // Limpia cualquier ruta anterior si es necesario
      _removePolyline(); // Reusa la función de limpieza de polilíneas
      _highestTraversedPointIndex = -1; // Reiniciar
      setState(() {
        routeCoordinates.clear(); // Limpiar
        routeSegmentsCoordinates.clear(); // Limpiar
        _routeSteps.clear(); // Limpiar
        _currentRouteStepIndex = 0;
        _isNavigating = false;
      });
      return;
    }

    print('🌟 coordinates ${selectedPoints.length}');
    String coordinatesString = selectedPoints
        .map((point) => '${point.coordinates.lng},${point.coordinates.lat}')
        .join(';');

    final String accessToken = widget.mapboxAccessToken;
    final String url =
        '$baseUrl/$coordinatesString?access_token=$accessToken&geometries=geojson&overview=full&steps=true&language=es&annotations=congestion';
    print('🌟 url $url');
    print('🌟 url ${await http.get(Uri.parse(url))}');

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          print('✅ Ruta obtenida exitosamente.');

          // *** CAMBIO CLAVE AQUÍ: Asigna el modelo una sola vez ***
          mapboxModel = mapbox_model.mapboxModelFromJson(response.body);
          print('DEBUG: mapboxModel asignado.');

          // Accede a la ruta principal del modelo
          final mapbox_model.Route? route = mapboxModel!.routes?.first;

          if (route != null) {
            // Poblar routeCoordinates directamente desde la geometría de la ruta principal
            if (route.geometry?.coordinates != null) {
              routeCoordinates =
                  route.geometry!.coordinates!
                      .map(
                        (coordPair) =>
                            mapbox.Position(coordPair[0], coordPair[1]),
                      )
                      .toList();
              print(
                'DEBUG: routeCoordinates poblada con ${routeCoordinates.length} puntos desde el modelo.',
              );
            } else {
              print(
                '⚠️ Advertencia: route.geometry.coordinates es nulo o vacío en el modelo.',
              );
              // Puedes tener un fallback aquí si realmente necesitas iterar sobre los steps si la geometría principal falta.
              // Por ahora, confiaremos en overview=full para llenar route.geometry.coordinates.
              routeCoordinates
                  .clear(); // Asegúrate de que esté vacía si no se puede poblar.
            }

            // Poblar _routeSteps desde el modelo (combinando todos los steps de todos los legs)
            _routeSteps.clear();
            if (route.legs != null) {
              for (var leg in route.legs!) {
                if (leg.steps != null) {
                  _routeSteps.addAll(
                    leg.steps!.map((s) => s.toJson()),
                  ); // Convierte Step model a Map<String,dynamic> para tu _routeSteps List<dynamic>
                }
              }
            }
            print('DEBUG: _routeSteps tiene ${_routeSteps.length} pasos.');

            // Procesar información de tráfico y crear segmentos
            await getTrafficList(route); // Pasa la ruta del modelo directamente
            await createCoordinatesSegments(
              legList: route.legs!,
            ); // Pasa los legs del modelo
            print(
              'DEBUG: getTrafficList y createCoordinatesSegments completados.',
            );
          } else {
            print('⚠️ El modelo no contiene rutas válidas.');
            routeCoordinates.clear();
            _routeSteps.clear();
            routeVisualSegments.clear();
            trafficSegments.clear();
            _highestTraversedPointIndex = -1;
          }

          setState(() {
            _currentRouteStepIndex = 0;
            _hasSpokenInstructionForCurrentStep = false;
          });

          // Llamada a _addRouteToMap()
          await _addPolyline(); // Asegúrate de que esta línea esté descomentada aquí.
          print('DEBUG: _addRouteToMap() completado desde _getRoute().');
        } else {
          print(
            '⚠️ No se encontraron rutas válidas en la respuesta de Mapbox.',
          );
          _showSnackBar(
            'No se pudo encontrar una ruta para los puntos seleccionados.',
          );
          routeCoordinates.clear();
          _routeSteps.clear();
          routeVisualSegments.clear();
          trafficSegments.clear();
          _highestTraversedPointIndex = -1;
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
        print('❌ $errorMessage');
        _showSnackBar(errorMessage);
        routeCoordinates.clear();
        _routeSteps.clear();
        routeVisualSegments.clear();
        trafficSegments.clear();
        _highestTraversedPointIndex = -1;
      }
    } catch (e) {
      print('❌ Excepción al obtener la ruta: $e');
      _showSnackBar(
        'Ocurrió un error al intentar obtener la ruta. Verifica tu conexión.',
      );
      routeCoordinates.clear();
      _routeSteps.clear();
      routeVisualSegments.clear();
      trafficSegments.clear();
      _highestTraversedPointIndex = -1;
      clearRouteRlatedState();
    }
  }

  Future<void> getTrafficList(mapbox_model.Route routeModel) async {
    print(
      '🌟 getTrafficList: Procesando niveles de congestión para la ruta...',
    );

    // Limpiar listas anteriores antes de rellenar
    congestionList.clear();
    trafficIndexesList.clear();
    trafficSegments.clear(); // Limpiamos los segmentos de tráfico anteriores

    if (routeModel.legs == null || routeModel.legs!.isEmpty) {
      print(
        '⚠️ Advertencia: No hay legs en el modelo de ruta para procesar congestión.',
      );
      return;
    }

    // Acumularemos todas las coordenadas de la ruta completa para referencia.
    // Esto ya debería estar en `routeCoordinates` de tu `_getRoute` function,
    // pero lo hacemos aquí por seguridad y claridad al asociar la congestión.
    List<mapbox.Position> fullRouteCoordinatesFromModel = [];
    // Usamos la geometría completa de la ruta si está disponible (overview=full)
    if (routeModel.geometry != null &&
        routeModel.geometry!.coordinates != null) {
      fullRouteCoordinatesFromModel =
          routeModel.geometry!.coordinates!
              .map((coordPair) => mapbox.Position(coordPair[0], coordPair[1]))
              .toList();
    } else {
      // Si no, concatenamos las geometrías de los pasos de cada leg
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

    // Índice para recorrer `fullRouteCoordinatesFromModel`
    int globalCoordinateIndex = 0;

    // Iterar a través de cada 'leg' (tramo) de la ruta
    for (int legIndex = 0; legIndex < routeModel.legs!.length; legIndex++) {
      final currentLeg = routeModel.legs![legIndex];

      if (currentLeg.annotation == null ||
          currentLeg.annotation!.congestion == null) {
        print(
          'ℹ️ Leg $legIndex no tiene anotaciones de congestión. Saltando este leg.',
        );
        // Incrementar el globalCoordinateIndex por las coordenadas de este leg si no tiene congestión
        // Esto es crucial para mantener la alineación si los legs tienen geometrías propias.
        if (currentLeg.steps != null) {
          for (var step in currentLeg.steps!) {
            if (step.geometry != null && step.geometry!.coordinates != null) {
              globalCoordinateIndex += step.geometry!.coordinates!.length;
            }
          }
        }
        continue; // Pasa al siguiente leg si no hay datos de congestión
      }

      final List<mapbox_model.Congestion> congestionLevelsForLeg =
          currentLeg.annotation!.congestion!;

      // Iterar sobre los niveles de congestión de este leg
      for (int i = 0; i < congestionLevelsForLeg.length; i++) {
        String currentCongestionLevelString = "unknown"; // Default
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

        // Si el nivel no es UNKNOWN, lo añadimos a la lista de índices de tráfico.
        // Este índice se refiere al índice dentro de la lista 'congestionList' combinada.
        if (congestionLevelsForLeg[i] != mapbox_model.Congestion.UNKNOWN) {
          trafficIndexesList.add(congestionList.length - 1);
        }

        // Para crear `MapboxFeature`s para la visualización de tráfico:
        // Mapbox Directions API proporciona la congestión para *segmentos* de la polilínea.
        // Cada elemento en `congestionLevelsForLeg` corresponde a un segmento entre
        // `(globalCoordinateIndex + i)` y `(globalCoordinateIndex + i + 1)` en la
        // `fullRouteCoordinatesFromModel`.

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
      // Después de procesar todos los segmentos de congestión de este leg,
      // actualiza el `globalCoordinateIndex` para el inicio del siguiente leg.
      // Esto es crucial si la congestión está indexada por la geometría total de la ruta.
      // Si la congestión se aplica a cada punto consecutivo del leg.geometry.coordinates,
      // entonces sumamos la longitud de las coordenadas de los pasos del leg.
      if (currentLeg.steps != null) {
        for (var step in currentLeg.steps!) {
          if (step.geometry != null && step.geometry!.coordinates != null) {
            globalCoordinateIndex += step.geometry!.coordinates!.length;
          }
        }
      }
    }
    print(
      '✅ Finalizado el procesamiento de congestión. Total de segmentos de congestión: ${trafficSegments.length}',
    );
  }

  Future<void> createCoordinatesSegments({
    required List<mapbox_model.Leg> legList,
  }) async {
    print(
      '🌟 createCoordinatesSegments: Iniciando segmentación de la ruta (Solución de Continuidad)...',
    );

    routeVisualSegments.clear(); // Limpiar segmentos visuales anteriores

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
      print(
        '⚠️ createCoordinatesSegments: mapboxModel o sus rutas/legs son nulos/vacíos. Saliendo.',
      );
      return;
    }

    int globalSegmentCounter = 0;
    mapbox.Position?
    lastSegmentEndPoint; // Almacena el último punto del segmento anterior

    for (
      int stepIndex = 0;
      stepIndex < effectiveRouteSteps.length;
      stepIndex++
    ) {
      final currentStep = effectiveRouteSteps[stepIndex];

      if (currentStep.geometry == null ||
          currentStep.geometry!.coordinates == null ||
          currentStep.geometry!.coordinates!.isEmpty) {
        continue;
      }

      List<mapbox.Position> stepCoords =
          currentStep.geometry!.coordinates!
              .map((coordPair) => mapbox.Position(coordPair[0], coordPair[1]))
              .toList();

      int currentStepCoordIndex =
          0; // Índice de inicio para el segmento actual dentro del step

      // Reinicia el lastSegmentEndPoint al inicio de cada nuevo STEP
      // ya que los steps no garantizan continuidad en sus límites.
      if (stepIndex > 0) {
        lastSegmentEndPoint =
            null; // No hay superposición entre steps por defecto.
      }

      while (currentStepCoordIndex < stepCoords.length) {
        List<mapbox.Position> segmentCoords = [];

        // *** CLAVE PARA LA CONTINUIDAD ***
        // Si no es el primer segmento de este step, añadir el último punto del segmento anterior.
        if (lastSegmentEndPoint != null) {
          segmentCoords.add(lastSegmentEndPoint);
        } else if (currentStepCoordIndex > 0 && stepCoords.isNotEmpty) {
          // Si es el primer segmento pero no el primer punto general,
          // y el step no es el primero, podría ser un caso de borde.
          // Aquí aseguramos que si un segmento empieza después de otro, su primer punto es el último del anterior.
          // Sin embargo, `lastSegmentEndPoint` es más fiable.
          // Si estamos dividiendo un STEP, y no es el inicio del step (currentStepCoordIndex > 0),
          // entonces el punto anterior (currentStepCoordIndex - 1) es el último del 'segmento' anterior
          // dentro de este step.
          if (segmentCoords.isEmpty) {
            // Solo si no se ha añadido ya por `lastSegmentEndPoint`
            segmentCoords.add(stepCoords[currentStepCoordIndex - 1]);
          }
        }

        // Calcular el índice final del segmento (inclusive)
        int segmentEndIndex =
            (currentStepCoordIndex + _segmentPointsThreshold - 1);
        if (segmentEndIndex >= stepCoords.length) {
          segmentEndIndex =
              stepCoords.length - 1; // Asegurarse de no exceder los límites
        }

        // Añadir los puntos para el segmento actual (empezando desde currentStepCoordIndex)
        for (int i = currentStepCoordIndex; i <= segmentEndIndex; i++) {
          segmentCoords.add(stepCoords[i]);
        }

        // Actualizar el punto final del último segmento creado para la próxima iteración
        if (segmentCoords.isNotEmpty) {
          lastSegmentEndPoint = segmentCoords.last;
        }

        // Asegurarse de que el segmento tenga al menos 2 puntos para formar una LineString
        // Si segmentCoords.length es 1 después de añadir `lastSegmentEndPoint`, y no hay más,
        // entonces solo tendríamos 1 punto, lo cual no es una línea.
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
          print(
            '⚠️ Segmento generado con menos de 2 puntos (${segmentCoords.length}), omitido.',
          );
        }

        // AVANZAR currentStepCoordIndex para la PRÓXIMA iteración del while.
        // El siguiente segmento debe empezar en el punto `segmentEndIndex`.
        currentStepCoordIndex = segmentEndIndex;
        // Solo incrementamos si no estamos en el último punto, para no exceder.
        if (currentStepCoordIndex < stepCoords.length - 1) {
          currentStepCoordIndex++; // Avanza al siguiente punto, que será el inicio del próximo segmento.
        } else {
          // Si estamos en el último punto del step, salimos del bucle para este step
          currentStepCoordIndex = stepCoords.length;
        }
      }
    }

    print(
      '✅ Segmentación de ruta completada. Total de segmentos visuales creados: ${routeVisualSegments.length}',
    );

    // Verificación de continuidad (¡MUY IMPORTANTE PARA DEPURAR ESTO!)
    if (routeVisualSegments.length > 1) {
      for (int i = 0; i < routeVisualSegments.length - 1; i++) {
        final currentSegEnd = routeVisualSegments[i].coordinates.last;
        final nextSegStart = routeVisualSegments[i + 1].coordinates.first;

        // Usamos una pequeña tolerancia para la comparación de flotantes
        const double epsilon = 1e-9;

        if ((currentSegEnd.lng - nextSegStart.lng).abs() > epsilon ||
            (currentSegEnd.lat - nextSegStart.lat).abs() > epsilon) {
          print('❌ Discrepancia de continuidad entre segmento ${i} y ${i + 1}');
          print(
            '   Fin segmento ${i}: (${currentSegEnd.lng}, ${currentSegEnd.lat})',
          );
          print(
            '   Inicio segmento ${i + 1}: (${nextSegStart.lng}, ${nextSegStart.lat})',
          );
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
    // Asegúrate de que _mapboxMapController no sea nulo antes de continuar
    if (_mapboxMapController == null || !_isMapReady) {
      print(
        '❌ Error: _mapboxMapController es nulo o el mapa aún no esta listo. No se pueden crear marcadores.',
      );
      return []; // Retorna una lista vacía si el controlador no está listo
    }

    // Carga la imagen del asset
    final ByteData bytes = await rootBundle.load(assetPaTh);
    final Uint8List list = bytes.buffer.asUint8List();

    // Inicializa el pointAnnotationManager si es nulo.
    // Esto es una buena salvaguarda si no se inicializó en onMapCreated.
    pointAnnotationManager ??=
        await _mapboxMapController!.annotations.createPointAnnotationManager();

    // Esta lista almacenará los marcadores que se crearán y se devolverán
    List<mapbox.PointAnnotation> createdValidMarkers = [];

    if (isUserMarker) {
      // --- Lógica para el Marcador del Usuario ---
      if (userMarker != null) {
        try {
          await pointAnnotationManager!.delete(userMarker!);
          // Limpia la referencia después de la eliminación exitosa
          userMarker = null;
          print('✅ Marcador de usuario anterior eliminado.');
        } catch (e) {
          print(
            '⚠️ Advertencia: Error al intentar eliminar marcador de usuario anterior: $e',
          );
        }
      }

      // Crear las opciones para el nuevo marcador del usuario
      mapbox.PointAnnotationOptions option = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        // La imagen cargada del asset
        image: list,
        // Un texto descriptivo
        textField: 'Mi Ubicación',
        // Color para el texto del marcador
        textColor: Colors.blue.value,
      );

      // Crea el nuevo marcador y asigna su referencia a userMarker
      userMarker = await pointAnnotationManager!.create(option);
      if (userMarker != null) {
        createdValidMarkers.add(userMarker!); // Añadir a la lista a devolver
        print('✅ Marcador de usuario creado en Lat: $lat, Lng: $lng');
      } else {
        print('⚠️ Fallo al crear el marcador de usuario.');
      }
    } else {
      // --- Lógica para Otros Marcadores (Destinos) ---
      mapbox.PointAnnotationOptions option = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        image: list, // La imagen cargada
      );

      // Usamos createMulti incluso para uno solo, es una API flexible y devuelve una lista.
      final List<mapbox.PointAnnotation?> createdMarkersWithNulls =
          await pointAnnotationManager!.createMulti([
            option,
          ]); // createMulti espera una lista

      // Filtrar cualquier null y añadir solo los marcadores válidos
      final List<mapbox.PointAnnotation> validMarkersFromMulti =
          createdMarkersWithNulls.whereType<mapbox.PointAnnotation>().toList();

      _destinationMarkers.addAll(
        validMarkersFromMulti,
      ); // Añadir a la lista global de destinos
      createdValidMarkers.addAll(
        validMarkersFromMulti,
      ); // Añadir a la lista a devolver
      print(
        '✅ Marcador adicional creado en Lat: $lat, Lng: $lng. Añadido a _destinationMarkers y devuelto.',
      );
    }

    // No necesitamos setState() aquí. La creación/actualización/eliminación de anotaciones
    // en Mapbox Maps Flutter ya actualiza el mapa directamente.
    // El setState() si fuera necesario sería en el widget padre si la UI de Flutter (fuera del mapa)
    // necesita reflejar cambios en _destinationMarkers o userMarker.
    // if (mounted) {
    //   setState(() {});
    // }

    return createdValidMarkers; // Siempre devuelve una lista de marcadores válidos
  }

  Future<void> _setNavigationPerspective({
    required double targetLat,
    required double targetLng,
    double zoom = 15.0, // Zoom por defecto
    double pitch = 50.0, // Inclinación por defecto para vista 3D
    double bearing = 0.0, // 0 grados = Norte arriba por defecto
  }) async {
    if (_mapboxMapController == null) {
      print('Error: MapboxMapController no está inicializado.');
      return;
    }

    final cameraOptions = mapbox.CameraOptions(
      center: mapbox.Point(
        coordinates: mapbox.Position(targetLng, targetLat),
      ), // Longitud, Latitud
      zoom: zoom,
      pitch: pitch, // Inclinación en grados
      bearing: bearing, // Rotación en grados (0-360)
    );

    // Usamos flyTo para una animación suave y natural
    await _mapboxMapController!.flyTo(
      cameraOptions,
      mapbox.MapAnimationOptions(
        duration: 1000,
      ), // Duración de la animación en ms
    );

    print(
      'Perspectiva del mapa cambiada a: Lat $targetLat, Lng $targetLng, Zoom $zoom, Pitch $pitch, Bearing $bearing',
    );
  }

  void _startNavigation() async {
    print('🟡 _startNavigation: Iniciando navegación...');

    _highestTraversedPointIndex = -1; // Asegurarse de que se reinicia
    _lastTraversedSegmentIndex = -1; // Asegurarse de que se reinicia
    _currentRouteStepIndex = 0; // Asegurarse de que se reinicia
    // Asegurarse de que se reinicia
    _hasSpokenInstructionForCurrentStep = false;

    setState(() {
      // Establecer el estado de navegación
      _isNavigating = true;
    });

    // 1. Obtener la ruta completa de Mapbox.
    // _getRoute() ya debe poblar this.routeCoordinates con la geometría completa
    // y this._routeSteps con todos los pasos.
    await _getRoute();

    // --- ELIMINAR ESTA LÍNEA ---
    // routeCoordinates = []; // Esto borraría las coordenadas que _getRoute acaba de obtener.
    // -------------------------

    // 2. Crear los segmentos visuales de la ruta para el seguimiento dinámico.
    // Esta función usará this.routeCoordinates.
    await createCoordinatesSegments(legList: mapboxModel!.routes![0].legs!);
    // Nota: Si `createCoordinatesSegments` ya llena `this.routeCoordinates` internamente,
    // y `_getRoute` también, asegúrate de que no haya duplicación o conflicto.
    // Idealmente, `_getRoute` llena `routeCoordinates` y `createCoordinatesSegments` la usa.

    // setState(() {
    // 3. Añadir marcadores para los puntos de destino.
    // selectedPoints ya debe contener los puntos seleccionados por el usuario.
    // _getRoute() inserta el _currentPosition al inicio de la ruta,
    // pero esos no deben tener un marcador 'red_marker'.
    // Los selectedPoints son solo tus destinos intermedios y finales.
    // Asegúrate de que selectedPoints no incluya el punto inicial de la ruta
    // insertado por _getRoute() si no quieres un marcador rojo en el inicio.
    // for (var i = 0; i < selectedPoints.length; i++) {
    //   createMarker(
    //     assetPaTh: 'assets/red_marker.png',
    //     lat: selectedPoints[i].coordinates.lat.toDouble(),
    //     lng: selectedPoints[i].coordinates.lng.toDouble(),
    //     isUserMarker: false, // Estos no son el marcador del usuario
    //   );
    // }

    // --- ELIMINAR ESTE BUCLE ---
    // for (var i = 0; i < mapboxGeometry.length; i++) {
    //   // Esto es redundante si _getRoute ya pobló routeCoordinates
    //   routeCoordinates.add(
    //     mapbox.Position(mapboxGeometry[i][0], mapboxGeometry[i][1]),
    //   );
    // }
    // -------------------------

    // 4. Dibujar la polilínea inicial de la ruta (todos los segmentos).
    // Ahora, _addPolyline() debería usar `routeVisualSegments`.
    // La llamada Future.delayed(Duration.zero) no es necesaria si `routeCoordinates`
    // y `routeVisualSegments` ya están listos.
    // Llama a _addRouteToMap() que dibujará la ruta base y posiblemente los segmentos de tráfico.

    // Lo mantengo por si hay alguna inicialización tardía del mapa
    await _addPolyline(); // Usaremos esta para dibujar la ruta segmentada

    // Establecer el estado de navegación
    // _isNavigating = true;

    if (_currentPosition != null) {
      await createMarker(
        assetPaTh: 'assets/navigation.png', // Marcador de navegación
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
        isUserMarker: true,
      );
      print(
        '📍 Marcador de usuario cambiado a navegación (DESPUÉS de la ruta).',
      );
    }

    setState(() {
      for (var i = 0; i < selectedPoints.length; i++) {
        createMarker(
          assetPaTh: 'assets/red_marker.png',
          lat: selectedPoints[i].coordinates.lat.toDouble(),
          lng: selectedPoints[i].coordinates.lng.toDouble(),
          isUserMarker: false, // Estos no son el marcador del usuario
        );
      }
    });

    // 5. Reproducir la primera instrucción de voz.
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
    // if (_routeSteps.isNotEmpty) {
    //   // Asegúrate de que _routeSteps ya esté poblada por _getRoute()
    //   flutterTts.speak(_routeSteps.first['maneuver']['instruction']);
    //   _currentRouteStepIndex++;
    //   _hasSpokenInstructionForCurrentStep = true; // Marcar que ya se habló
    // }
    // });

    _listMapLayers(); // Para depuración
    print('✅ _startNavigation: Navegación iniciada.');
  }

  void _stopNavigation() async {
    // Hacerlo async para el await de delete
    print('🔴 _stopNavigation: Deteniendo navegación...');
    setState(() {
      _isNavigating = false;
      _addedLocations = [];
    });

    // Limpiar todas las polilíneas de la ruta y los marcadores de destino
    await _removePolyline(); // Eliminar la ruta segmentada (base y recorrida)
    await _removeAllDestinationMarkers(); // Necesitarás crear esta función

    // Limpiar estados relacionados con la ruta
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
    _lastConsumedSegmentIndex = -1;
    _lastTraversedSegmentIndex = -1;
    _highestTraversedPointIndex = -1;
    selectedPoints = [];

    // Si también quieres detener el stream de ubicación:
    // positionStreamSubscription?.cancel();

    print('✅ _stopNavigation: Navegación detenida y ruta eliminada.');
  }

  void clearRouteRlatedState() {
    routeCoordinates.clear();
    routeSegmentsCoordinates.clear(); //
    _routeSteps.clear();
    routeVisualSegments.clear();
    trafficSegments.clear();
    _highestTraversedPointIndex = -1;
    _currentRouteStepIndex = 0;
    _isNavigating = false;
    _hasSpokenInstructionForCurrentStep = false;
    _lastTraversedSegmentIndex = -1;
    _lastConsumedSegmentIndex = -1;
    // También limpiar los selectedPoints si es apropiado para tu lógica
    selectedPoints.clear();
    _addedLocations.clear(); // Limpiar la lista de UI también
    _removeAllDestinationMarkers(); // Eliminar marcadores del mapa
  }

  // Nueva función auxiliar para eliminar todos los marcadores de destino
  // Asume que los marcadores de destino se pueden distinguir del marcador de usuario
  // o que se guardan sus referencias en una lista separada.
  Future<void> _removeAllDestinationMarkers() async {
    if (pointAnnotationManager == null) {
      print('ℹ️ _removeAllDestinationMarkers: pointAnnotationManager es nulo.');
      return;
    }

    if (_destinationMarkers.isNotEmpty) {
      try {
        // *** CAMBIO CLAVE AQUÍ: Eliminar marcadores uno por uno ***
        for (var marker in _destinationMarkers) {
          await pointAnnotationManager!.delete(marker);
          print('DEBUG: Marcador ${marker.id} eliminado.');
        }

        _destinationMarkers.clear(); // Limpiar la lista después de eliminarlos
        print('✅ Todos los marcadores de destino eliminados exitosamente.');
      } catch (e) {
        print('❌ Error al eliminar marcadores de destino: $e');
      }
    } else {
      print('ℹ️ No hay marcadores de destino para eliminar.');
    }
    // if (pointAnnotationManager != null) {
    //   // Si tus marcadores de destino no están en una lista separada,
    //   // podrías necesitar una forma de distinguirlos o simplemente
    //   // borrarlos todos excepto el de usuario.
    //   // Una opción es mantener una List<PointAnnotation> para los destinos.
    //   // Por ahora, asumiré que los marcadores de destino se añadirán a una lista interna
    //   // o que puedes diferenciarlos.

    //   // Ejemplo (requiere almacenar los IDs de los marcadores de destino):
    //   // if (destinationMarkers.isNotEmpty) {
    //   //   await pointAnnotationManager!.deleteMulti(destinationMarkers.map((m) => m.id).toList());
    //   //   destinationMarkers.clear();
    //   // }

    //   // O si solo tienes el marcador de usuario y los de destino y quieres borrarlos todos
    //   // excepto el de usuario, sería más complejo sin IDs específicos.
    //   // La forma más fácil es mantener una lista de PointAnnotation para los destinos.

    //   // Placeholder: Puedes implementar la lógica específica aquí.
    //   print('ℹ️ Implementar _removeAllDestinationMarkers si es necesario.');
    // }
  }

  //v2 gemini
  String _toHexColorString(int argbValue) {
    // Mask out the alpha channel (0xFFFFFF) and convert to 6-digit hex
    return '#${(argbValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Future<void> _addPolyline() async {
    if (_mapboxMapController == null) return;

    print(
      '🌟 _addRouteToMap: Añadiendo la ruta base de segmentos (para borrado)...',
    );

    // 1. Limpiar TODAS las capas y fuentes relevantes existentes
    // Esto asegura un lienzo limpio.
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
    // Si tenías capas de tráfico y quieres asegurarte de que también se limpien al inicio:
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

    // Limpiar cualquier PolylineAnnotation residual (como la línea azul anterior)
    _polylineAnnotationManager ??=
        await _mapboxMapController!.annotations
            .createPolylineAnnotationManager();
    // Eliminar cualquier _traversedPolyline residual si existía
    if (_traversedPolyline != null) {
      await _polylineAnnotationManager!.delete(_traversedPolyline!);
      _traversedPolyline = null;
    }

    // 2. Preparar y añadir la Capa Base de Segmentos (Morado/Naranja que se hará transparente)
    List<mapbox.Feature> baseSegmentFeatures = [];
    for (var visualSegment in routeVisualSegments) {
      baseSegmentFeatures.add(
        mapbox.Feature(
          id: visualSegment.id, // ID único del segmento
          geometry: mapbox.LineString(coordinates: visualSegment.coordinates),
          properties: {
            'segment_number': visualSegment.segmentNumber,
            'is_traversed':
                visualSegment.isTraversed, // Inicialmente false para todos
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
          id: 'route-base-segments-source', // Fuente para los segmentos de la ruta base
          data: jsonEncode(baseSegmentFeatureCollection.toJson()),
        ),
      );

      await _mapboxMapController!.style.addLayer(
        mapbox.LineLayer(
          id: 'route-base-segments-layer', // Capa para los segmentos de la ruta base
          sourceId: 'route-base-segments-source',
          lineWidth: 5.0,
          lineJoin: mapbox.LineJoin.ROUND,
          lineCap: mapbox.LineCap.ROUND,
          // EXPRESIÓN CLAVE: Si 'is_traversed' es true, el color es transparente
          lineColorExpression: [
            'case',
            [
              '==',
              [
                '%',
                ['get', 'segment_number'],
                2,
              ],
              0,
            ], // Si es par
            _toHexColorString(Colors.purple.toARGB32()),
            _toHexColorString(
              Colors.orange.toARGB32(),
            ), // Si es impar (fallback)
          ],
          // *** ¡AÑADE EL FILTRO AQUÍ! ***
          filter: [
            '==', // Opera el filtro como 'si esta propiedad es igual a este valor'
            [
              'get',
              'is_hidden',
            ], // Obtiene el valor de la propiedad 'is_hidden'
            false, // Solo muestra la Feature si 'is_hidden' es FALSE
          ],
          // lineColorExpression: [
          //   'case',
          //   [
          //     '==',
          //     ['get', 'is_traversed'],
          //     true,
          //   ], // Si el segmento está recorrido
          //   // _toHexColorString(Colors.white.toARGB32()), // <-- ¡PRUEBA CON ESTE!
          //   // O si ves que el fondo es un gris muy claro, puedes probar:
          //   _toHexColorString(Colors.grey[50]!.toARGB32()),
          //   // _toHexColorStringRGB(Colors.grey[100]!.toARGB32()),

          //   // Si el segmento NO está recorrido (colores par/impar)
          //   [
          //     '==',
          //     [
          //       '%',
          //       ['get', 'segment_number'],
          //       2,
          //     ],
          //     0,
          //   ], // Si es par
          //   _toHexColorString(Colors.purple.toARGB32()),
          //   _toHexColorString(
          //     Colors.orange.toARGB32(),
          //   ), // Si es impar (fallback)
          // ],
          // lineColorExpression: [
          //   'case',
          //   [
          //     '==',
          //     [
          //       '%',
          //       ['get', 'segment_number'],
          //       2,
          //     ],
          //     0,
          //   ], // Si es par
          //   _toHexColorString(Colors.purple.toARGB32()),
          //   _toHexColorString(
          //     Colors.orange.toARGB32(),
          //   ), // Si es impar (fallback)
          // ],
          // *** CAMBIO 2: line-opacity controlara la visibilidad (borrado) ***
          // lineOpacityExpression: [
          //   'case',
          //   [
          //     '==',
          //     ['get', 'is_traversed'],
          //     true,
          //   ], // Si 'is_traversed' es true
          //   0.0, // Opacidad 0.0 (completamente transparente)
          //   1.0, // Opacidad 1.0 (completamente opaco, su color original)
          // ],
          // lineWidthExpression: [
          //   'case',
          //   [
          //     '==',
          //     ['get', 'is_traversed'],
          //     true,
          //   ], // Si el segmento está recorrido
          //   0.0, // Ancho 0.0 (invisible)
          //   5.0, // Ancho 5.0 (visible si no está recorrido)
          // ],
          // lineColorExpression: [
          //   'match',
          //   ['get', 'is_traversed'], // Pregunta por la propiedad 'is_traversed'
          //   true, // Si es TRUE (segmento recorrido)
          //   _toHexColorString(
          //     Colors.transparent.toARGB32(),
          //   ), // Hacemos el segmento COMPLETAMENTE TRANSPARENTE
          //   // Si es FALSE (segmento NO recorrido) o la propiedad no existe
          //   [
          //     '%',
          //     ['get', 'segment_number'],
          //     2,
          //   ], // Lógica original par/impar
          //   0,
          //   _toHexColorString(Colors.purple.toARGB32()),
          //   1,
          //   _toHexColorString(Colors.orange.toARGB32()),
          //   _toHexColorString(Colors.grey.toARGB32()), // Fallback
          // ],
        ),
      );
      print('DEBUG: Capa route-base-segments-layer AÑADIDA.');
    }

    // Ya no necesitamos añadir capas de tráfico aquí si el objetivo es solo el borrado.
    // Si las quieres de vuelta, asegúrate de que se añadan AQUÍ, después de la capa base de segmentos.

    // Ya no inicializamos _traversedPolyline (la línea azul)
    // porque el objetivo es solo borrar los segmentos base.

    // Forzar un setState inicial para asegurar que todo se renderice
    if (mounted) {
      setState(() {});
    }

    print('✅ _addRouteToMap: Ruta base de segmentos añadida exitosamente.');
  }

  Future<void> _listMapLayers() async {
    if (_mapboxMapController == null) return;

    try {
      // Usar getStyleLayers() para obtener un listado de los IDs de las capas
      final allLayerIds = await _mapboxMapController!.style.getStyleLayers();

      print('✅ Capas actuales en el mapa (IDs):');
      for (var layerId in allLayerIds) {
        print('  - ID: ${layerId!.id}');
        // Si necesitas el tipo o más propiedades, tendrías que obtener la capa individualmente
        // y luego acceder a sus propiedades. Por ejemplo:
        // final layer = await _mapboxMapController!.style.getLayer(layerId);
        // print('    Type: ${layer.type}'); // Esto puede variar dependiendo del tipo de capa
      }
    } catch (e) {
      print('❌ Error al listar las capas del mapa: $e');
    }
  }

  Future<void> _removePolyline() async {
    if (_mapboxMapController == null) return;

    print('🔴 _removePolyline: Iniciando eliminación de capas de ruta.');

    // Eliminar la capa y fuente de SEGMENTOS BASE (morado/naranja)
    if (await _mapboxMapController!.style.styleLayerExists(
      'route-base-segments-layer',
    )) {
      await _mapboxMapController!.style.removeStyleLayer(
        'route-base-segments-layer',
      );
      print('✅ Capa de segmentos base (route-base-segments-layer) eliminada.');
    }
    if (await _mapboxMapController!.style.styleSourceExists(
      'route-base-segments-source',
    )) {
      await _mapboxMapController!.style.removeStyleSource(
        'route-base-segments-source',
      );
      print(
        '✅ Fuente de segmentos base (route-base-segments-source) eliminada.',
      );
    }

    // Eliminar cualquier capa de tráfico si existía y también quieres limpiarla
    if (await _mapboxMapController!.style.styleLayerExists(
      'route-traffic-layer',
    )) {
      await _mapboxMapController!.style.removeStyleLayer('route-traffic-layer');
      print('✅ Capa de tráfico (route-traffic-layer) eliminada.');
    }
    if (await _mapboxMapController!.style.styleSourceExists(
      'route-traffic-source',
    )) {
      await _mapboxMapController!.style.removeStyleSource(
        'route-traffic-source',
      );
      print('✅ Fuente de tráfico (route-traffic-source) eliminada.');
    }

    // Eliminar cualquier PolylineAnnotation residual (como la línea azul anterior)
    // Asegurarse de que el manager está inicializado antes de intentar usarlo
    if (_polylineAnnotationManager != null) {
      if (_traversedPolyline != null) {
        try {
          await _polylineAnnotationManager!.delete(_traversedPolyline!);
          _traversedPolyline = null;
          print('✅ _traversedPolyline (línea azul anterior) eliminada.');
        } catch (e) {
          print('⚠️ Advertencia: Error al eliminar _traversedPolyline: $e');
        }
      }
      // Si _unTraversedPolyline existe (aunque ya no lo usamos en esta estrategia), también limpiarlo
      if (_unTraversedPolyline != null) {
        try {
          await _polylineAnnotationManager!.delete(_unTraversedPolyline!);
          _unTraversedPolyline = null;
          print('✅ _unTraversedPolyline (línea verde anterior) eliminada.');
        } catch (e) {
          print('⚠️ Advertencia: Error al eliminar _unTraversedPolyline: $e');
        }
      }
    }

    print('✅ _removePolyline: Limpieza de capas de ruta completada.');
  }

  // Métodos para manejar el zoom
  Future<void> _zoomIn() async {
    if (_mapboxMapController != null) {
      mapbox.CameraState cs = await _mapboxMapController!.getCameraState();
      mapbox.CameraOptions co = mapbox.CameraOptions(
        center: cs.center,
        zoom: cs.zoom + 1, // Aumenta el zoom en 1 nivel
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
      // Asegúrate de no ir por debajo del zoom mínimo (generalmente 0)
      if (cs.zoom > 0) {
        mapbox.CameraOptions co = mapbox.CameraOptions(
          center: cs.center,
          zoom: cs.zoom - 1, // Disminuye el zoom en 1 nivel
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
          _suggestions = []; // Limpiar sugerencias si el campo está vacío
        });
      }
    });
  }

  Future<void> _getPlaceSuggestions(String pattern) async {
    print('🌟 get places');
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

    print('💖 response $url');

    try {
      final response = await http.get(url);
      print('💖 response ${response.body}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        // final properties = data['properties'];
        setState(() {
          _suggestions =
              features.map((feature) {
                return {
                  // 'name': feature['place_name'],
                  'name': feature['properties']['name'],
                  'coordinates':
                      feature['geometry']['coordinates'], // [longitude, latitude]
                };
              }).toList();
        });
      } else {
        print('Error en la API de Mapbox Geocoding: ${response.statusCode}');
        setState(() {
          _suggestions = [];
        });
        // return [];
      }
    } catch (e) {
      print('Error al obtener sugerencias de lugares: $e');
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

    // Agrega o actualiza un marcador en el mapa
    // createMarker ahora devuelve una lista
    final createdMarkers = await createMarker(
      assetPaTh: 'assets/red_marker.png',
      lat: point.coordinates.lat.toDouble(),
      lng: point.coordinates.lng.toDouble(),
      isUserMarker: false,
    );

    // createMarker añade el marcador a _destinationMarkers internamente.
    // Pero aquí necesitamos la referencia específica para este item en _addedLocations.
    mapbox.PointAnnotation? markerReference;
    if (createdMarkers.isNotEmpty) {
      // Si createMulti (dentro de createMarker) devolvió un solo marcador, tómalo.
      markerReference = createdMarkers.first;
    }

    setState(() {
      _addedLocations.add({
        'name': name,
        'point': point,
        //guarda la referencia del marcador
        'marker': markerReference,
      });
    });

    _searchController.text = name;

    // Mueve el mapa a la ubicación seleccionada
    _mapboxMapController?.setCamera(
      mapbox.CameraOptions(center: point, zoom: 14.0),
    );

    // _addOrUpdateSearchMarker(point, name);

    // Ocultar el teclado
    FocusScope.of(context).unfocus();
    //Limpiar el search controller
    _searchController.clear();
  }

  Future<void> _checkRouteProgress() async {
    if (!_isNavigating || _currentPosition == null) {
      return;
    }

    // Lógica para las instrucciones de voz (basada en _routeSteps)
    if (_currentRouteStepIndex < _routeSteps.length) {
      print('🔴🔴🔴 for _if currentroutestepindex');
      // final currentStep = _routeSteps[_currentRouteStepIndex];
      // final instruction = currentStep['maneuver']['instruction'];
      // final double maneuverLat = currentStep['maneuver']['location'][1];
      // final double maneuverLng = currentStep['maneuver']['location'][0];

      // Correctly access as Map<String, dynamic>
      final Map<String, dynamic> currentStep =
          _routeSteps[_currentRouteStepIndex]
              as Map<String, dynamic>; // <-- Corrected casting
      final instruction = currentStep['maneuver']['instruction'] as String;
      final double maneuverLat =
          (currentStep['maneuver']['location'][1] as num).toDouble();
      final double maneuverLng =
          (currentStep['maneuver']['location'][0] as num).toDouble();

      // final mapbox_model.Step currentStep =
      //     _routeSteps[_currentRouteStepIndex]
      //         as mapbox_model.Step; // <-- Castear
      // <-- Notación de punto
      // final instruction = currentStep.maneuver!.instruction!;
      // // <-- Notación de punto
      // final double maneuverLat = currentStep.maneuver!.location![1];
      // // <-- Notación de punto
      // final double maneuverLng = currentStep.maneuver!.location![0];

      final double distanceToManeuver = geo.Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        maneuverLat,
        maneuverLng,
      );
      print('✅ Distance to mauneaver $distanceToManeuver');

      // print('Distancia a maniobra (${currentStep['name']}): $distanceToManeuver m. Instrucción: $instruction');

      // Umbral para decir la instrucción (ej. 100 metros antes de la maniobra)
      if (distanceToManeuver < 100 && !_hasSpokenInstructionForCurrentStep) {
        print('🔊 Instrucción de voz: $instruction');
        flutterTts.speak(instruction);
        _hasSpokenInstructionForCurrentStep = true;
        // _currentRouteStepIndex++;
        // Reset para la próxima instrucción
        // _hasSpokenInstructionForCurrentStep = false;
      }

      // Umbral para avanzar al siguiente paso de la ruta (cuando el usuario ha CERCANO o PASADO la maniobra)
      // Esto debería ser un umbral menor que el de "decir la instrucción".
      // Por ejemplo, si está a menos de 10 metros del punto de la maniobra
      //todo unncomment
      if (distanceToManeuver < 15 && _hasSpokenInstructionForCurrentStep) {
        print('⏩ Avanzando al siguiente paso: ${currentStep['name']}');
        _currentRouteStepIndex++;
        // Reset para la próxima instrucción
        _hasSpokenInstructionForCurrentStep = false;

        // Si hay más pasos, podríamos pre-cargar la siguiente instrucción o sus detalles aquí.
      }
    } else {
      // Si ya no hay más pasos, se ha llegado al final de la ruta lógica
      if (_isNavigating) {
        // Solo si aún estamos navegando
        flutterTts.speak('Has llegado a tu destino.');
        _stopNavigation();
        return;
      }
    }

    // Lógica para actualizar la visualización de la ruta recorrida (basada en routeVisualSegments)
    // Iterar solo los segmentos que aún no han sido marcados como recorridos
    bool shouldUpdateVisuals = false;
    for (
      int i = _lastTraversedSegmentIndex + 1;
      i < routeVisualSegments.length;
      i++
    ) {
      print('🟡🟡🟡 for lastraversed');
      print('🟡🟡🟡 for i $i');
      print('🟡🟡🟡 for lasttraversedsegmentindex $_lastTraversedSegmentIndex');
      final segment = routeVisualSegments[i];
      // Consideramos que un segmento ha sido recorrido si la posición actual del usuario
      // está muy cerca o ha pasado el *punto final* de ese segmento.
      // Usaremos el último punto del segmento como referencia.
      // Asegurarse de que el segmento tenga al menos 2 puntos
      if (segment.coordinates.length < 2) continue;

      // Último punto del segmento
      final segmentEndCoord = segment.coordinates.last;

      final double distanceToSegmentEnd = geo.Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        segmentEndCoord.lat.toDouble(),
        segmentEndCoord.lng.toDouble(),
      );

      print('✅ distance segment to end $distanceToSegmentEnd');

      // Umbral de 20 metros para considerar que un segmento ha sido "cruzado"
      // Puedes ajustar este umbral.
      if (distanceToSegmentEnd < 20) {
        if (!segment.isTraversed) {
          // Solo si no ha sido marcado
          segment.isTraversed = true;
          segment.isHidden = true; // <-- Establecer a true para ocultar
          _lastTraversedSegmentIndex = i;
          shouldUpdateVisuals = true;
          print(
            '✅ Segmento ${segment.id} marcado como recorrido y oculto. Nuevo _lastTraversedSegmentIndex: $_lastTraversedSegmentIndex. Activando actualización visual.',
          );
          // await _updateRouteVisuals();
        }
        // segment.isTraversed = true;
        // // Actualiza el último segmento recorrido
        // _lastTraversedSegmentIndex = i;
        print(
          '✅ Segmento ${segment.id} marcado como recorrido y oculto. Nuevo _lastTraversedSegmentIndex: $_lastTraversedSegmentIndex. Activando actualización visual.',
        );
        // print(
        //   '✅ Segmento ${segment.id} marcado como recorrido. Nuevo _lastTraversedSegmentIndex: $_lastTraversedSegmentIndex',
        // );
        // Llamamos a la actualización visual si un segmento ha cambiado de estado
        // await _updateRouteVisuals();
      } else {
        print(
          'DEBUG: Segmento $i no alcanzado. Distancia: ${distanceToSegmentEnd.toStringAsFixed(2)}m',
        );
        // Si el usuario no ha alcanzado el final de este segmento, no hay necesidad de revisar los siguientes
        break;
      }
    }
    // Llama _updateRouteVisuals SOLO si hubo un cambio en los segmentos recorridos
    if (shouldUpdateVisuals) {
      print(
        'DEBUG: _checkRouteProgress: Un segmento fue recorrido, llamando a _updateRouteVisuals().',
      );
      await _updateRouteVisuals();
    } else {
      print(
        'DEBUG: _checkRouteProgress: No hay nuevos segmentos recorridos en esta actualización.',
      );
    }
  }

  Future<void> _updateRouteVisuals() async {
    print(
      'DEBUG: === Entrando a _updateRouteVisuals() (BORRADO POR ELIMINACIÓN) ===',
    );

    if (_mapboxMapController == null) {
      print('⚠️ _updateRouteVisuals: _mapboxMapController es NULO. Saliendo.');
      return;
    }
    if (routeVisualSegments.isEmpty) {
      print(
        '⚠️ _updateRouteVisuals: routeVisualSegments está VACÍA. Saliendo.',
      );
      return;
    }

    // Paso 1: Construir la lista de FEATURES QUE DEBEN SEGUIR VISIBLES
    List<mapbox.Feature> remainingVisibleFeatures = [];
    String sourceIdToUpdate = 'route-base-segments-source';
    String layerIdToUpdate = 'route-base-segments-layer';

    for (int i = 0; i < routeVisualSegments.length; i++) {
      final visualSegment = routeVisualSegments[i];
      // ¡Solo añadimos la Feature si NO está oculta!
      if (!visualSegment.isHidden) {
        // <-- ¡LA CLAVE AQUÍ!
        remainingVisibleFeatures.add(
          mapbox.Feature(
            id: visualSegment.id,
            geometry: mapbox.LineString(coordinates: visualSegment.coordinates),
            properties: {
              'segment_number': visualSegment.segmentNumber,
              // Las propiedades 'is_traversed' y 'is_hidden' se mantendrían en tu modelo,
              // pero para esta Feature en el GeoJSON, ya no son tan críticas si no se usan en el filtro/expresión.
              // Las incluimos por completitud, pero lo importante es que el filtro ya no las evalúa.
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

    print(
      'DEBUG: GeoJSON ENVIADO A MAPBOX para actualización (solo visibles):',
    );
    print(
      '🆘 DEBUG: ${updatedGeoJsonString.length > 500 ? updatedGeoJsonString.substring(0, 500) + '...' : updatedGeoJsonString}',
    );
    if (remainingVisibleFeatures.isNotEmpty) {
      print('🆘 DEBUG: Ejemplo de Feature *VISIBLE* (primer segmento):');
      print('🆘 DEBUG: ${jsonEncode(remainingVisibleFeatures[0].toJson())}');
    } else {
      print(
        '🆘 DEBUG: remainingVisibleFeatures está vacía. Toda la ruta debería haber desaparecido.',
      );
    }

    // Paso 2: Remover y Añadir la Fuente y la Capa (como antes)
    try {
      bool layerExists = await _mapboxMapController!.style.styleLayerExists(
        layerIdToUpdate,
      );
      bool sourceExists = await _mapboxMapController!.style.styleSourceExists(
        sourceIdToUpdate,
      );
      print(
        'DEBUG: _updateRouteVisuals: Capa "$layerIdToUpdate" existe: $layerExists. Fuente "$sourceIdToUpdate" existe: $sourceExists.',
      );

      if (layerExists) {
        await _mapboxMapController!.style.removeStyleLayer(layerIdToUpdate);
        print('✅ Capa removida: $layerIdToUpdate');
      }
      if (sourceExists) {
        await _mapboxMapController!.style.removeStyleSource(sourceIdToUpdate);
        print('✅ Fuente removida: $sourceIdToUpdate');
      }

      await Future.delayed(Duration(milliseconds: 50));

      await _mapboxMapController!.style.addSource(
        mapbox.GeoJsonSource(
          id: sourceIdToUpdate,
          data:
              updatedGeoJsonString, // <-- ¡Ahora solo contiene los segmentos visibles!
        ),
      );
      print('✅ Fuente añadida de nuevo: $sourceIdToUpdate');

      await _mapboxMapController!.style.addLayer(
        mapbox.LineLayer(
          id: layerIdToUpdate,
          sourceId: sourceIdToUpdate,
          lineWidth: 5.0,
          lineJoin: mapbox.LineJoin.ROUND,
          lineCap: mapbox.LineCap.ROUND,
          // La expresión de color ahora NO necesita el filtro, porque solo dibuja lo que está en la fuente.
          lineColorExpression: [
            'case',
            [
              '==',
              [
                '%',
                ['get', 'segment_number'],
                2,
              ],
              0,
            ],
            _toHexColorString(Colors.purple.toARGB32()),
            _toHexColorString(Colors.orange.toARGB32()),
          ],
          // *** ¡ELIMINA EL FILTRO DE AQUÍ! ***
          // filter: [
          //   '==',
          //   ['get', 'is_hidden'],
          //   false,
          // ],
        ),
      );
      print('✅ Capa añadida de nuevo: $layerIdToUpdate');
    } catch (e) {
      print(
        '❌ ERROR en _updateRouteVisuals al remover/añadir fuente o capa: $e',
      );
      print('Stacktrace: ${e.toString()}');
    }
    print('DEBUG: === Saliendo de _updateRouteVisuals() ===');
  }

  Future<double> calculateDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) async {
    var p = 0.017453292519943295;
    var c = cos;
    var a =
        0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 1000 * 12742 * asin(sqrt(a));
  }

  Future<void> _removeSingleDestinationMarker(
    mapbox.PointAnnotation markerToRemove,
    int index,
  ) async {
    if (pointAnnotationManager == null) {
      print(
        'ℹ️ _removeSingleDestinationMarker: pointAnnotationManager es nulo.',
      );
      return;
    }

    print(
      '🔴 _removeSingleDestinationMarker: Eliminando marcador de destino individual: ${markerToRemove.id}',
    );

    try {
      await pointAnnotationManager!.delete(markerToRemove); // Eliminar del mapa
      _destinationMarkers.remove(
        markerToRemove,
      ); // Eliminar de la lista global de marcadores

      // *** CAMBIO CLAVE AQUÍ: Remover de _addedLocations y selectedPoints ***
      // Usa el index para remover del mismo índice en _addedLocations y selectedPoints
      setState(() {
        _addedLocations.removeAt(index);
        selectedPoints.removeAt(index);
      });

      print(
        '✅ Marcador ${markerToRemove.id} y lugar asociado eliminados exitosamente.',
      );

      // Opcional: Si quieres redibujar la ruta después de eliminar un punto
      // await _getRoute(); // Esto recalculará la ruta con los puntos restantes
      // await _addPolyline(); // Y la redibujará
    } catch (e) {
      print('❌ Error al eliminar marcador individual: $e');
    }
  }
}
