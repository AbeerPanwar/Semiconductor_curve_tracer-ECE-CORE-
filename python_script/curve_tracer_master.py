import serial
import time
import tkinter as tk
import sys
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.animation as animation

# --- CONFIGURATION ---
COM_PORT = 'COM4' 
BAUD_RATE = 115200

# --- 1. GUI COMPONENT SELECTOR ---
def get_target_file():
    selected_file, component_name, trigger_char = None, None, None
    def choose_bjt():
        nonlocal selected_file, component_name, trigger_char
        selected_file, component_name, trigger_char = 'bjt_output_data.csv', 'BJT', b'B\n'
        root.destroy()
    def choose_mosfet():
        nonlocal selected_file, component_name, trigger_char
        selected_file, component_name, trigger_char = 'mosfet_output_data.csv', 'MOSFET', b'M\n'
        root.destroy()

    root = tk.Tk()
    root.title("NSUT Curve Tracer - Final")
    root.geometry("400x180")
    root.eval('tk::PlaceWindow . center')
    tk.Label(root, text="Select Component in Socket:", font=("Segoe UI", 12, "bold")).pack(pady=15)
    btn_frame = tk.Frame(root)
    btn_frame.pack()
    tk.Button(btn_frame, text="BJT (2N3904)", command=choose_bjt, width=18, height=2, bg="#007acc", fg="white").pack(side=tk.LEFT, padx=10)
    tk.Button(btn_frame, text="MOSFET", command=choose_mosfet, width=18, height=2, bg="#d9534f", fg="white").pack(side=tk.RIGHT, padx=10)
    root.mainloop()
    return selected_file, component_name, trigger_char

OUTPUT_FILE, COMP_NAME, TRIGGER_CHAR = get_target_file()
if not OUTPUT_FILE: sys.exit()

# --- 2. ROBUST DATA LOGGING ---
print(f"🔌 Connecting to {COM_PORT}...")
try:
    ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=2)
    ser.setDTR(False)
    time.sleep(2) 
    ser.reset_input_buffer()
    
    print(f"🚀 Sweeping {COMP_NAME}...")
    ser.write(TRIGGER_CHAR) 
    ser.flush()
    
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write("Curve_Num,DAC1_Val,DAC2_Val,Raw_ADC\n")
        while True:
            if ser.in_waiting > 0:
                line = ser.readline().decode('utf-8', errors='ignore').strip()
                if not line or "Curve_Num" in line: continue
                
                if "--- SWEEP COMPLETE ---" in line:
                    print("🎉 Sweep Finished!")
                    break
                
                if line.count(',') == 3:
                    f.write(line + '\n')
                    f.flush()
    ser.close()
except Exception as e:
    print(f"❌ SERIAL ERROR: {e}"); sys.exit()

# --- 3. TRANSIMPEDANCE MATH ---
print("📈 Processing Data...")
df = pd.read_csv(OUTPUT_FILE)
df = df.apply(pd.to_numeric, errors='coerce').dropna()

# Convert ADC bits to Output Voltage (V_out)
df['V_Out_Volts'] = (df['Raw_ADC'] / 4095.0) * 3.3

# Convert DAC2 steps to Sweep Voltage (V_sweep)
df['V_Sweep_Volts'] = (df['DAC2_Val'] / 255.0) * 3.15 

# Calculate Current through 1k Ohm Resistor (I = V/R)
# Because R is 1000 Ohms, the voltage difference directly equals current in mA!
df['Current_mA'] = df['V_Out_Volts'] - df['V_Sweep_Volts']

# Filter noise
df.loc[df['Current_mA'] < 0, 'Current_mA'] = 0.0

# --- 4. ANIMATED PLOTTING ---
fig, ax = plt.subplots(figsize=(10, 6))
ax.set_title(f'{COMP_NAME} Characteristic Curves', fontsize=16, fontweight='bold')
ax.grid(True, linestyle="--", alpha=0.5)

ax.set_xlabel('Collector-Emitter Voltage ($V_{CE}$) [V]' if 'BJT' in COMP_NAME else 'Drain-Source Voltage ($V_{DS}$) [V]', fontsize=12)
ax.set_ylabel('Collector Current ($I_C$) [mA]' if 'BJT' in COMP_NAME else 'Drain Current ($I_D$) [mA]', fontsize=12)

# Dynamic Y-axis
y_max = df['Current_mA'].max() if df['Current_mA'].max() > 0.1 else 2.0
ax.set_ylim(0, y_max * 1.1)
ax.set_xlim(0, df['V_Sweep_Volts'].max() * 1.05)

curves = df['Curve_Num'].unique()
lines = [ax.plot([], [], lw=2.5, label=f'Step {int(c)}')[0] for c in curves]
ax.legend(title="Base Drive" if 'BJT' in COMP_NAME else "Gate Drive", loc='upper left')

def update(frame):
    for i, curve in enumerate(curves):
        c_data = df[df['Curve_Num'] == curve]
        if frame < len(c_data):
            x = c_data['V_Sweep_Volts'].iloc[:frame]
            y = c_data['Current_mA'].iloc[:frame]
            lines[i].set_data(x, y)
    return lines

ani = animation.FuncAnimation(fig, update, frames=len(df[df['Curve_Num'] == 1]) + 5, interval=15, blit=True, repeat=False)
plt.show()