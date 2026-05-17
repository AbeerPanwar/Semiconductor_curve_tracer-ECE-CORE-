#include <Arduino.h>
#include <WiFi.h>
#include <WebSocketsServer.h>
#include <Wire.h>
#include <Adafruit_ADS1X15.h>

// --- PINS ---
const int DAC1_PIN = 25; // Base/Gate Drive
const int DAC2_PIN = 26; // Sweep Voltage
// ADC_PIN 34 IS GONE! We use I2C Pins 21 & 22 now.

Adafruit_ADS1115 ads; // The ADS1115 module

const char *ssid = "NSUT_CurveTracer";
const char *password = "12345678";
WebSocketsServer webSocket = WebSocketsServer(81);

const int NUM_CURVES = 5;
const int SWEEP_MAX = 80;
const int SWEEP_STEP = 1;

char pendingCommand = '\0';
void runSweep(char cmd);

void webSocketEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length)
{
  if (type == WStype_TEXT)
  {
    char cmd = (char)payload[0];
    if (cmd == 'B' || cmd == 'b' || cmd == 'M' || cmd == 'm')
    {
      pendingCommand = cmd;
    }
  }
}

void setup()
{
  Serial.begin(115200);

  dacWrite(DAC1_PIN, 0);
  dacWrite(DAC2_PIN, 0);

  // Initialize I2C for ADS1115 on Pins 21 (SDA) and 22 (SCL)
  Wire.begin(21, 22);

  if (!ads.begin())
  {
    Serial.println("Failed to initialize ADS1115!");
    while (1)
      ;
  }
  // The default gain is 2/3 (+/- 6.144V), which is perfect for our 0-3.3V range.

  WiFi.softAP(ssid, password);
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
  delay(1000);
}

void loop()
{
  webSocket.loop();

  if (Serial.available() > 0)
  {
    pendingCommand = Serial.read();
  }

  if (pendingCommand != '\0')
  {
    char cmdToRun = pendingCommand;
    pendingCommand = '\0';
    runSweep(cmdToRun);
  }
}

void runSweep(char cmd)
{
  int driveSteps[NUM_CURVES];

  if (cmd == 'B' || cmd == 'b')
  {
    driveSteps[0] = 70;
    driveSteps[1] = 75;
    driveSteps[2] = 80;
    driveSteps[3] = 85;
    driveSteps[4] = 90;
  }
  else if (cmd == 'M' || cmd == 'm')
  {
    driveSteps[0] = 89;
    driveSteps[1] = 91;
    driveSteps[2] = 93;
    driveSteps[3] = 96;
    driveSteps[4] = 98;
  }
  else
  {
    return;
  }

  // Header now explicitly says ADS1115_mV
  Serial.println("Curve_Num,DAC1_Val,DAC2_Val,ADS1115_mV");
  webSocket.broadcastTXT("Curve_Num,DAC1_Val,DAC2_Val,ADS1115_mV");

  for (int c = 0; c < NUM_CURVES; c++)
  {
    dacWrite(DAC1_PIN, driveSteps[c]);
    delay(50);

    for (int dac2_val = 0; dac2_val <= SWEEP_MAX; dac2_val += SWEEP_STEP)
    {
      dacWrite(DAC2_PIN, dac2_val);
      delay(10);

      // Read directly in milli-volts from the ADS1115!
      int16_t adc0 = ads.readADC_SingleEnded(0);
      float volts = ads.computeVolts(adc0);
      int measured_mV = volts * 1000.0;

      String dataPacket = String(c + 1) + "," + String(driveSteps[c]) + "," + String(dac2_val) + "," + String(measured_mV);

      Serial.println(dataPacket);
      webSocket.broadcastTXT(dataPacket);
      webSocket.loop();
    }
    dacWrite(DAC2_PIN, 0);
  }
  dacWrite(DAC1_PIN, 0);
  Serial.println("--- SWEEP COMPLETE ---");
  webSocket.broadcastTXT("--- SWEEP COMPLETE ---");
}