import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const CurveTracerApp());
}

class CurveTracerApp extends StatelessWidget {
  const CurveTracerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NSUT Curve Tracer',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        primaryColor: const Color(0xFF0F3460),
      ),
      home: const TracerScreen(),
    );
  }
}

class TracerScreen extends StatefulWidget {
  const TracerScreen({super.key});

  @override
  State<TracerScreen> createState() => _TracerScreenState();
}

class _TracerScreenState extends State<TracerScreen> {
  late WebSocketChannel channel;
  bool isConnected = false;
  String currentComponent = "Ready to Test";

  // Store data points for the 5 curves
  final Map<int, List<FlSpot>> curveData = {1: [], 2: [], 3: [], 4: [], 5: []};

  final List<Color> curveColors = [
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.red,
    Colors.purple,
  ];

  @override
  void initState() {
    super.initState();
    connectWebSocket();
  }

  void connectWebSocket() {
    try {
      // The default IP for an ESP32 SoftAP is 192.168.4.1
      channel = WebSocketChannel.connect(Uri.parse('ws://192.168.4.1:81'));
      setState(() => isConnected = true);

      channel.stream.listen(
        (message) {
          handleIncomingData(message.toString().trim());
        },
        onError: (error) {
          setState(() => isConnected = false);
          print("WebSocket Error: $error");
        },
        onDone: () {
          setState(() => isConnected = false);
        },
      );
    } catch (e) {
      print("Connection Failed: $e");
    }
  }

  void handleIncomingData(String line) {
    if (line == "Curve_Num,DAC1_Val,DAC2_Val,Raw_ADC") {
      // Clear old graph data when a new sweep starts
      setState(() {
        for (var key in curveData.keys) {
          curveData[key]!.clear();
        }
      });
      return;
    }

    if (line == "--- SWEEP COMPLETE ---") return;

    // Parse CSV data: "Curve, DAC1, DAC2, ADC"
    List<String> parts = line.split(',');
    if (parts.length == 4) {
      int curveNum = int.tryParse(parts[0]) ?? 1;
      int dac2Val = int.tryParse(parts[2]) ?? 0;
      int rawAdc = int.tryParse(parts[3]) ?? 0;

      // --- TRANSIMPEDANCE MATH (Translated from Python) ---
      double vOutVolts = (rawAdc / 4095.0) * 3.3;
      double vSweepVolts = (dac2Val / 255.0) * 3.15; // 3.15V Calibration

      double currentMA = vOutVolts - vSweepVolts;
      if (currentMA < 0) currentMA = 0.0; // Filter noise

      // Update the chart
      setState(() {
        curveData[curveNum]?.add(FlSpot(vSweepVolts, currentMA));
      });
    }
  }

  void triggerSweep(String component, String command) {
    if (isConnected) {
      setState(() => currentComponent = "Sweeping $component...");
      channel.sink.add(command);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not connected to ESP32 WiFi!")),
      );
    }
  }

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Phase 4: Wireless Tracer',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF16213E),
        actions: [
          Icon(
            isConnected ? Icons.wifi : Icons.wifi_off,
            color: isConnected ? Colors.greenAccent : Colors.redAccent,
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              currentComponent,
              style: const TextStyle(fontSize: 18, color: Colors.white70),
            ),
          ),

          // --- THE CHART ---
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: true),
                  titlesData: FlTitlesData(
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      axisNameWidget: const Text(
                        "Voltage (V)",
                        style: TextStyle(color: Colors.white70),
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      axisNameWidget: const Text(
                        "Current (mA)",
                        style: TextStyle(color: Colors.white70),
                      ),
                      axisNameSize: 20,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.white24),
                  ),
                  minX: 0,
                  maxX: 3.2,
                  minY: 0,
                  maxY: 3.0, // Adjust based on your max current
                  lineBarsData: _buildChartLines(),
                ),
                duration: const Duration(
                  milliseconds: 0,
                ), // Instant update
              ),
            ),
          ),

          // --- CONTROLS ---
          Container(
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF16213E),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.analytics),
                  label: const Text("Test BJT"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                  onPressed: () => triggerSweep("BJT", "B"),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.bolt),
                  label: const Text("Test MOSFET"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                  onPressed: () => triggerSweep("MOSFET", "M"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper to generate the lines for fl_chart
  List<LineChartBarData> _buildChartLines() {
    List<LineChartBarData> lines = [];
    for (int i = 1; i <= 5; i++) {
      if (curveData[i]!.isNotEmpty) {
        lines.add(
          LineChartBarData(
            spots: curveData[i]!,
            isCurved: true,
            color: curveColors[i - 1],
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false), // Hide dots for performance
          ),
        );
      }
    }
    return lines;
  }
}
