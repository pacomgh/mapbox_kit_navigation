library mapbox_navigation_kit;

import 'package:flutter/widgets.dart';

// Exporta el widget principal y las clases de modelo que el usuario puede necesitar
export 'src/widgets/navigation_map.dart';
export 'src/models/mapbox_model.dart';
export 'src/models/route_segment_visual.dart';
export 'src/models/mapbox_feature.dart';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

void initializeMapboxNavigationKit({required String accessToken}) {
  // Asegurarse de que el binding de Flutter esté inicializado,
  // aunque `main()` de la app consumidora ya debería hacerlo.
  // Es una buena práctica ponerlo aquí para mayor seguridad si este método
  // fuera llamado muy temprano.
  WidgetsFlutterBinding.ensureInitialized();

  // Configurar el token de acceso de Mapbox
  mapbox.MapboxOptions.setAccessToken(accessToken);
  print('✅ Mapbox Navigation Kit: Access Token configurado exitosamente.');
}
