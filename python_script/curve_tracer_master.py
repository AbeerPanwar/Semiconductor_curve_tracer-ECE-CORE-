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
    selected_file = None
    component_name = None
    trigger_char = None

    def choose_bjt():
        nonlocal selected_file, component_name, trigger_char
        selected_file = 'bjt_output_data.csv'
        component_name = 'BJT'
        trigger_char = b'B' 
        root.destroy()

    def choose_mosfet():
        nonlocal selected_file, component_name, trigger_char
        selected_file = 'mosfet_output_data.csv'
        component_name = 'MOSFET'
        trigger_char = b'M' 
        root.destroy()

    root = tk.Tk()
    root.title("Curve Tracer - Run Test")
    root.geometry("380x150")
    root.eval('tk::PlaceWindow . center')
    root.attributes('-topmost', True)

    tk.Label(root, text="Select the component in the Test Socket:", font=("Segoe UI", 11)).pack(pady=20)
    btn_frame = tk.Frame(root)
    btn_frame.pack()
    tk.Button(btn_frame, text="Test BJT", command=choose_bjt, width=15, bg="#007acc", fg="white").pack(side=tk.LEFT, padx=10)
    tk.Button(btn_frame, text="Test MOSFET", command=choose_mosfet, width=15, bg="#d9534f", fg="white").pack(side=tk.RIGHT, padx=10)
    root.mainloop()
    
    return selected_file, component_name, trigger_char

OUTPUT_FILE, COMP_NAME, TRIGGER_CHAR = get_target_file()
if not OUTPUT_FILE:
    print("❌ Cancelled.")
    sys.exit()

# --- 2. AUTOMATED DATA LOGGING ---
print(f"🔌 Connecting to {COM_PORT}...")
try:
    ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=2)
    time.sleep(2) 
    ser.reset_input_buffer()
    
    print(f"🚀 Instructing hardware to test {COMP_NAME}...")
    ser.write(TRIGGER_CHAR) 
    ser.flush()
    
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        recording = False
        while True:
            if ser.in_waiting > 0:
                line = ser.readline().decode('utf-8', errors='ignore').strip()
                
                if "--- SWEEP COMPLETE ---" in line:
                    print("🎉 Sweep Finished!")
                    break
                
                if "Curve_Num" in line:
                    recording = True
                    print("📊 Receiving Data...")
                    f.write(line + '\n')
                elif recording:
                    f.write(line + '\n')
                    
    ser.close()
except Exception as e:
    print(f"❌ ERROR: {e}")
    sys.exit()

# --- 3. AUTOMATED PLOTTING ---
print("📈 Plotting curves...")

df = pd.read_csv(OUTPUT_FILE)
df = df.apply(pd.to_numeric, errors='coerce').dropna() 

df['ADS1115_mV'] = pd.to_numeric(df['ADS1115_mV'])
df['DAC2_Val'] = pd.to_numeric(df['DAC2_Val'])

df['V_Sweep_Volts'] = (df['DAC2_Val'] / 255.0) * 3.3
df['V_Sweep_mV'] = df['V_Sweep_Volts'] * 1000.0

# Calculate voltage drop across the 1 kOhm resistor
df['Voltage_Drop_mV'] = df['ADS1115_mV'] - df['V_Sweep_mV']

# Filter noise
df.loc[df['Voltage_Drop_mV'] < 0, 'Voltage_Drop_mV'] = 0.0 

# Math for 1 kOhm Resistor: Current in mA
df['Current_mA'] = df['Voltage_Drop_mV'] / 1000.0

# Dynamic Labels
if "MOSFET" in COMP_NAME:
    y_label = 'Drain Current ($I_D$) [mA]' # Back to mA
    x_label = 'Drain-Source Voltage ($V_{DS}$) [Volts]'
    legend_title = "Gate Drive"
else:
    y_label = 'Collector Current ($I_C$) [mA]' # Back to mA
    x_label = 'Collector-Emitter Voltage ($V_{CE}$) [Volts]'
    legend_title = "Base Drive"

# Setup the Figure
fig, ax = plt.subplots(figsize=(10, 6))
fig.canvas.manager.set_window_title(f'{COMP_NAME} Test Results')

ax.set_title(f'{COMP_NAME} Output Characteristics', fontsize=16, fontweight='bold')
ax.set_xlabel(x_label, fontsize=12)
ax.set_ylabel(y_label, fontsize=12)
ax.grid(True, linestyle="--", alpha=0.7)

ax.set_xlim(0, df['V_Sweep_Volts'].max() * 1.05)
ax.set_ylim(0, df['Current_mA'].max() * 1.1)

curves = df['Curve_Num'].unique()
lines = []
for curve in curves:
    line, = ax.plot([], [], linewidth=2, label=f'Step {int(curve)}')
    lines.append(line)

ax.legend(title=legend_title)
plt.tight_layout()

max_points = df.groupby('Curve_Num').size().max() if not df.empty else 100

def init():
    for line in lines:
        line.set_data([], [])
    return lines

def update(frame):
    for i, curve in enumerate(curves):
        curve_data = df[df['Curve_Num'] == curve]
        x_data = curve_data['V_Sweep_Volts'].iloc[:frame]
        y_data = curve_data['Current_mA'].iloc[:frame]
        lines[i].set_data(x_data, y_data)
    return lines

ani = animation.FuncAnimation(fig, update, frames=max_points + 5,
                              init_func=init, blit=True, interval=15, repeat=False)

plt.show()