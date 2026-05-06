# HR-display

Simple macOS menubar-only heart rate monitor that reads Bluetooth heart-rate broadcasts.

![photo menu bar widget](assets/hr-display-example.png)

## Installation

1. Clone the repo to your `/Applications` folder
2. Build and bundle the app:
   ```sh
   ./bundle.sh
   ```

## Launching the App

The app runs as a menubar-only application (no Dock icon). Launch it from:
- **Spotlight**: Press Cmd+Space and search for "HR-display"
- **Launchpad**: Find it in your applications
- **Terminal**: `open HR-display.app`

## Usage

1. Put your heart rate monitor or smart watch into heart-rate broadcast mode.
2. Launch the app and allow Bluetooth access when macOS asks.
3. The menubar item will update with the live heart rate once the device is discovered.

The app listens for the standard Bluetooth Heart Rate Service, so any compatible HR broadcaster should work.
