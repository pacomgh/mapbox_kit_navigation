# mapbox_kit_navigation

A comprehensive navigation package for Flutter that integrates the powerful capabilities of Mapbox with a fluid and customizable user experience. `mapbox_kit_navigation` allows you to easily add place search functionality, real-time traffic-aware route calculation, turn-by-turn voice navigation, and dynamic route progress visualization.

---

## Features

* **Integrated Place Search:** Allows users to search for and select destinations with real-time suggestions, with the ability to add multiple stops to the route.
* **Dynamic Route Calculation:** Get optimal routes from the user's current location or from predefined points, using the Mapbox Directions API.
* **Traffic Visualization:** Displays congestion levels on the route, helping users understand traffic conditions.
* **Turn-by-Turn Navigation:** Provides clear and concise voice instructions for each turn and maneuver, guiding the user along the route.
* **Dynamic Route Progress:** The route visually updates in real-time, "hiding" traversed sections for an intuitive experience.
* **Navigation Camera Control:** The map camera automatically follows the user's position, adjusting the perspective for an optimal navigation view.
* **Custom Marker Personalization:** Support for custom user location and destination markers.
* **Zoom Controls:** Simple map zoom-in and zoom-out functionality.
* **Route Management:** Functions to easily start, stop, and clear routes.

---

## Installation

1.  **Add the dependency** to your `pubspec.yaml` file:

    ```yaml
    dependencies:
      mapbox_kit_navigation: ^0.0.1
    ```

2.  **Run `flutter pub get`** in your terminal.

---

## Mapbox Setup

To use this package, you'll need a Mapbox access token.

1.  **Create a Mapbox account:** If you don't have one, sign up at [mapbox.com](https://www.mapbox.com/).
2.  **Get your access token:** Go to your [Mapbox Dashboard](https://account.mapbox.com/) and copy your **public access token**.

### Platform-Specific Configuration

**Android:**

Add your Mapbox access token to the `android/gradle.properties` file:

```properties
MAPBOX_DOWNLOADS_TOKEN=YOUR_MAPBOX_ACCESS_TOKEN

```
In android/app/src/main/AndroidManifest.xml, add the necessary location permissions:

```properties

<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>

    <!-- Other configurations-->
</manifest>
```

iOS:

In your ios/Runner/Info.plist file, add:

```properties

<key>MGLMapboxAccessToken</key>
<string>YOUR_MAPBOX_ACCESS_TOKEN</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs your location to show you on the map and provide navigation.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs your location to show you on the map and provide navigation.</string>
```

And in ios/Podfile, ensure the minimum platform is enabled:

```properties
platform :ios, '12.0' # or higher
```

## Usage

On your main add this import

```properties
//other imports
import 'package:mapbox_kit_navigation/mapbox_navigation_kit.dart' as mapbox_navigation_kit;
```

On your main function add this

```properties
void main() {
// Other configurations
  mapbox_navigation_kit.initializeMapboxNavigationKit(
    //can you set here your variable
    accessToken: 'YOUR_MAPBOX_TOKEN',
  );

  //Other things
}

```

Using Navigation map widget example:

```properties

@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Navigation App')),
      body: const NavigationMap(
        mapboxAccessToken: 'YOUR_MAPBOX_TOKEN',
        //To use a places searchbar 
        showSearchBar: true,
        //if you have a list with your places coordinates use this
        routeCoordinatesList: [
          [longitude, latitude],
        ],
      ),
    );
  }

```

## Contributions
Contributions are welcome! If you find a bug or have an idea for a new feature, feel free to open an issue or submit a pull request on the GitHub repository.

## License
This package is licensed under the Apache License, Version 2.0. See the LICENSE file for more details.