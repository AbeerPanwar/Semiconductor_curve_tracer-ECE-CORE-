#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_ADS1X15.h>

Adafruit_ADS1115 ads;

const int DAC1_PIN = 25;
const int DAC2_PIN = 26;
const int NUM_CURVES = 5;

void setup()
{
  Serial.begin(115200);
  ads.setGain(GAIN_ONE);
  if (!ads.begin())
  {
    Serial.println("Failed to initialize ADS1115!");
    while (1)
      ;
  }
  dacWrite(DAC1_PIN, 0);
  dacWrite(DAC2_PIN, 0);
}

void loop()
{
  if (Serial.available() > 0)
  {
    char cmd = Serial.read();
    int baseSteps[NUM_CURVES];

    if (cmd == 'B' || cmd == 'b')
    {
      // BJT is sensitive: Send lower voltages
      baseSteps[0] = 48;
      baseSteps[1] = 51;
      baseSteps[2] = 54;
      baseSteps[3] = 57;
      baseSteps[4] = 60;
    }
    else if (cmd == 'M' || cmd == 'm')
    {
      // MOSFET is stubborn: Crank the DAC to maximum to open the gate
      baseSteps[0] = 82;
      baseSteps[1] = 85;
      baseSteps[2] = 88;
      baseSteps[3] = 91;
      baseSteps[4] = 94;
    }
    else
    {
      return; // Ignore weird serial noise
    }

    Serial.println("Curve_Num,DAC1_Val,DAC2_Val,OpAmp_mV");

    for (int c = 0; c < NUM_CURVES; c++)
    {
      dacWrite(DAC1_PIN, baseSteps[c]);
      delay(500);

      for (int dac2_val = 0; dac2_val <= 80; dac2_val += 1)
      {
        dacWrite(DAC2_PIN, dac2_val);
        delay(10);

        int16_t adc0 = ads.readADC_SingleEnded(0);
        float mv0 = ads.computeVolts(adc0) * 1000.0;

        Serial.print(c + 1);
        Serial.print(",");
        Serial.print(baseSteps[c]);
        Serial.print(",");
        Serial.print(dac2_val);
        Serial.print(",");
        Serial.println(mv0, 3);
      }
      dacWrite(DAC2_PIN, 0);
    }
    dacWrite(DAC1_PIN, 0);
    Serial.println("--- SWEEP COMPLETE ---");
  }
}