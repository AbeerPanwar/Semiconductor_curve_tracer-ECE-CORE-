#include <Arduino.h>
#include <WiFi.h>
#include <WebSocketsServer.h>

// --- HARDWARE PIN MAPPING ---
const int DAC1_PIN = 25; // Base/Gate Drive
const int DAC2_PIN = 26; // Sweep Voltage
const int ADC_PIN = 34;  // Op-Amp Output (Current Measurement)

// --- NETWORK SETUP ---
const char *ssid = "NSUT_CurveTracer";             // The Wi-Fi network name
const char *password = "12345678";                 // The Wi-Fi password (must be 8+ chars)
WebSocketsServer webSocket = WebSocketsServer(81); // WebSocket server on port 81

const int NUM_CURVES = 5;
const int SWEEP_MAX = 220;
const int SWEEP_STEP = 2;

// --- FUNCTION PROTOTYPE (THIS FIXES THE ERROR) ---
void runSweep(char cmd);

// Function to handle messages from the Flutter App
void webSocketEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length)
{
  if (type == WStype_TEXT)
  {
    char cmd = (char)payload[0];
    if (cmd == 'B' || cmd == 'b' || cmd == 'M' || cmd == 'm')
    {
      Serial.printf("Received command from Wi-Fi: %c\n", cmd);
      runSweep(cmd); // Trigger the sweep!
    }
  }
}

void setup()
{
  Serial.begin(115200);
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  dacWrite(DAC1_PIN, 0);
  dacWrite(DAC2_PIN, 0);

  // Start the Wi-Fi Access Point
  Serial.println("Starting Wi-Fi Access Point...");
  WiFi.softAP(ssid, password);
  Serial.print("ESP32 IP Address: ");
  Serial.println(WiFi.softAPIP()); // Usually 192.168.4.1

  // Start the WebSocket Server
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
  Serial.println("WebSocket Server started on port 81");

  delay(1000);
}

void loop()
{
  // Keep the WebSocket server listening
  webSocket.loop();

  // Keep listening to the USB Cable (for Python)
  if (Serial.available() > 0)
  {
    char cmd = Serial.read();
    runSweep(cmd);
  }
}

// --- THE SWEEP LOGIC ---
void runSweep(char cmd)
{
  int driveSteps[NUM_CURVES];

  if (cmd == 'B' || cmd == 'b')
  {
    driveSteps[0] = 50;
    driveSteps[1] = 90;
    driveSteps[2] = 130;
    driveSteps[3] = 170;
    driveSteps[4] = 210;
  }
  else if (cmd == 'M' || cmd == 'm')
  {
    driveSteps[0] = 155;
    driveSteps[1] = 165;
    driveSteps[2] = 175;
    driveSteps[3] = 190;
    driveSteps[4] = 205;
  }
  else
  {
    return;
  }

  // Broadcast Header to both Python and Flutter
  Serial.println("Curve_Num,DAC1_Val,DAC2_Val,Raw_ADC");
  webSocket.broadcastTXT("Curve_Num,DAC1_Val,DAC2_Val,Raw_ADC");

  for (int c = 0; c < NUM_CURVES; c++)
  {
    dacWrite(DAC1_PIN, driveSteps[c]);
    delay(100);

    for (int dac2_val = 0; dac2_val <= SWEEP_MAX; dac2_val += SWEEP_STEP)
    {
      dacWrite(DAC2_PIN, dac2_val);
      delay(5);

      long sum = 0;
      for (int i = 0; i < 64; i++)
      {
        sum += analogRead(ADC_PIN);
      }
      int raw_reading = (int)(sum / 64);

      // Build the data packet
      String dataPacket = String(c + 1) + "," + String(driveSteps[c]) + "," + String(dac2_val) + "," + String(raw_reading);

      // DUAL BROADCAST: Send to USB and Wi-Fi simultaneously
      Serial.println(dataPacket);
      webSocket.broadcastTXT(dataPacket);
    }
    dacWrite(DAC2_PIN, 0);
    delay(50);
  }
  dacWrite(DAC1_PIN, 0);
  Serial.println("--- SWEEP COMPLETE ---");
  webSocket.broadcastTXT("--- SWEEP COMPLETE ---");
}