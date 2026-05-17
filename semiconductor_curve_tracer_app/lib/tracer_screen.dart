import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:fl_chart/fl_chart.dart';

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
      
      channel.ready.then((_) {
        if (mounted) {
          setState(() => isConnected = true);
        }
      }).catchError((error) {
        if (mounted) {
          setState(() => isConnected = false);
        }
      });

      channel.stream.listen(
        (message) {
          handleIncomingData(message.toString().trim());
        },
        onError: (error) {
          if (mounted) setState(() => isConnected = false);
        },
        onDone: () {
          if (mounted) setState(() => isConnected = false);
        },
      );
    } catch (e) {
      if (mounted) setState(() => isConnected = false);
      throw Exception("Failed to connect to WebSocket");
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

  Future<void> _handleRefresh() async {
    try {
      channel.sink.close();
    } catch (_) {}
    
    setState(() {
      isConnected = false;
      currentComponent = "Ready to Test";
      for (var key in curveData.keys) {
        curveData[key]!.clear();
      }
    });
    connectWebSocket();
    await Future.delayed(const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Wireless Semiconductor Characterization',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: true,
              child: Column(
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
              child: Stack(
                children: [
                  Column(
                    children: [
                      const Text(
                        "BJT Output Characteristics",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: LineChart(
                          LineChartData(
                            lineTouchData: const LineTouchData(enabled: false),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: true,
                              getDrawingHorizontalLine: (value) => const FlLine(
                                color: Colors.white12,
                                strokeWidth: 1,
                                dashArray: [5, 5],
                              ),
                              getDrawingVerticalLine: (value) => const FlLine(
                                color: Colors.white12,
                                strokeWidth: 1,
                                dashArray: [5, 5],
                              ),
                            ),
                            titlesData: FlTitlesData(
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                axisNameWidget: const Padding(
                                  padding: EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    "Collector-Emitter Voltage (Vce) [Volts]",
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ),
                                axisNameSize: 30,
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  getTitlesWidget: (value, meta) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        value.toStringAsFixed(1),
                                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                axisNameWidget: const Text(
                                  "Collector Current (Ic) [mA]",
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                axisNameSize: 24,
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toStringAsFixed(1),
                                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                                      textAlign: TextAlign.right,
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(color: Colors.white24),
                            ),
                            minX: 0,
                            maxX: _maxX,
                            minY: 0,
                            maxY: _maxY,
                            lineBarsData: _buildChartLines(),
                          ),
                          duration: const Duration(milliseconds: 0), // Instant update
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 40,
                    right: 8,
                    child: _buildLegend(),
                  ),
                ],
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
            ),
          ],
        ),
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
            barWidth: 2, // Slightly thinner line to match Python plot
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false), // Hide dots for performance
          ),
        );
      }
    }
    return lines;
  }

  double get _maxX {
    double max = 1.1; // Default matching Python plot
    for (var curve in curveData.values) {
      for (var spot in curve) {
        if (spot.x > max) max = spot.x;
      }
    }
    return max > 1.1 ? max : 1.1;
  }

  double get _maxY {
    double max = 2.2; // Default matching Python plot
    for (var curve in curveData.values) {
      for (var spot in curve) {
        if (spot.y > max) max = spot.y;
      }
    }
    return max > 2.2 ? max : 2.2;
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E).withOpacity(0.9), // Match background
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Base Drive",
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 2, color: curveColors[i]),
                  const SizedBox(width: 4),
                  Text("Step ${i + 1}", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            )
        ],
      ),
    );
  }
}
