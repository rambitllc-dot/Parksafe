import SwiftUI

/// Debug panel — only visible in TestFlight builds
/// Shows real-time parking detection status and allows manual testing
struct ParkingDebugView: View {
@EnvironmentObject var detector: ParkingDetector

```
var body: some View {
    NavigationView {
        ScrollView {
            VStack(spacing: 16) {

                // Status card
                VStack(alignment: .leading, spacing: 10) {
                    Text("Parking Status")
                        .font(.headline)
                        .foregroundColor(.white)
                    HStack {
                        Circle()
                            .fill(detector.isParked ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        Text(detector.isParked ? "Parked" : "Not parked")
                            .foregroundColor(.white)
                    }
                    if detector.isParked {
                        Text("Street: \(detector.parkedStreetName)")
                            .foregroundColor(.green)
                            .font(.subheadline)
                        if let coord = detector.parkedCoordinate {
                            Text("Lat: \(String(format: "%.6f", coord.latitude))")
                                .foregroundColor(.gray)
                                .font(.caption)
                            Text("Lon: \(String(format: "%.6f", coord.longitude))")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        if let time = detector.parkedAt {
                            Text("Parked at: \(time.formatted(date: .omitted, time: .shortened))")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.12))
                .cornerRadius(16)

                // Test buttons
                VStack(spacing: 12) {
                    Text("Test Controls")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        detector.testParkHere()
                    } label: {
                        Label("📍 Simulate: I Parked Here", systemImage: "car.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }

                    Button {
                        detector.testNotificationIn10Seconds()
                    } label: {
                        Label("🔔 Test Notification (10 sec)", systemImage: "bell.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }

                    Button {
                        detector.clearParked()
                    } label: {
                        Label("🚗 Clear Parked Location", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                }
                .padding()
                .background(Color(white: 0.12))
                .cornerRadius(16)

                // Debug log
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Debug Log")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Clear") {
                            detector.debugLog.removeAll()
                        }
                        .foregroundColor(.gray)
                        .font(.caption)
                    }

                    if detector.debugLog.isEmpty {
                        Text("No logs yet...")
                            .foregroundColor(.gray)
                            .font(.caption)
                    } else {
                        ForEach(detector.debugLog, id: \.self) { entry in
                            Text(entry)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
                .background(Color(white: 0.08))
                .cornerRadius(16)
            }
            .padding()
        }
        .background(Color(white: 0.07).ignoresSafeArea())
        .navigationTitle("🧪 Debug Panel")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

}
