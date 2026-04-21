import serial
import time
import tkinter as tk
import sys
import pandas as pd
import matplotlib.pyplot as plt

# --- CONFIGURATION ---
COM_PORT = 'COM8'  # Update if necessary
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
        trigger_char = b'B\n'
        root.destroy()

    def choose_mosfet():
        nonlocal selected_file, component_name, trigger_char
        selected_file = 'mosfet_output_data.csv'
        component_name = 'MOSFET'
        trigger_char = b'M\n'
        root.destroy()

    root = tk.Tk()
    root.title("Curve Tracer - Run Test")
    root.geometry("380x150")
    root.eval('tk::PlaceWindow . center')
    root.attributes('-topmost', True)

    tk.Label(root, text="Select the component in the Test Socket:", font=("Segoe UI", 11)).pack(pady=20)
    btn_frame = tk.Frame(root)
    btn_frame.pack()
    tk.Button(btn_frame, text="BJT (2N3904)", command=choose_bjt, width=15, bg="#007acc", fg="white").pack(side=tk.LEFT, padx=10)
    tk.Button(btn_frame, text="MOSFET", command=choose_mosfet, width=15, bg="#d9534f", fg="white").pack(side=tk.RIGHT, padx=10)
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
    
    print(f"🚀 Instructing hardware to test {COMP_NAME}...")
    ser.write(TRIGGER_CHAR) 
    
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        recording = False
        while True:
            if ser.in_waiting > 0:
                line = ser.readline().decode('utf-8', errors='ignore').strip()
                
                if "Curve_Num" in line:
                    recording = True
                    print("📊 Receiving Data...")
                    f.write(line + '\n')
                elif recording:
                    f.write(line + '\n')
                    if "--- SWEEP COMPLETE ---" in line:
                        print("🎉 Sweep Finished!")
                        break
    ser.close()
except Exception as e:
    print(f"❌ ERROR: {e}")
    sys.exit()

# --- 3. AUTOMATED PLOTTING ---
print("📈 Plotting curves...")
import matplotlib.animation as animation

df = pd.read_csv(OUTPUT_FILE)

df = df[df['Curve_Num'] != '--- SWEEP COMPLETE ---']
df['Curve_Num'] = pd.to_numeric(df['Curve_Num'])
df['OpAmp_mV'] = pd.to_numeric(df['OpAmp_mV'])
df['DAC2_Val'] = pd.to_numeric(df['DAC2_Val'])

df['V_Sweep_Volts'] = (df['DAC2_Val'] / 255.0) * 3.3
df['V_Sweep_mV'] = df['V_Sweep_Volts'] * 1000.0
df['Voltage_Drop_mV'] = df['OpAmp_mV'] - df['V_Sweep_mV']
df.loc[df['Voltage_Drop_mV'] < 0, 'Voltage_Drop_mV'] = 0.0 
df['Current_mA'] = df['Voltage_Drop_mV'] / 1000.0

# Dynamic Labels based on component type
if "MOSFET" in COMP_NAME:
    y_label = 'Drain Current ($I_D$) [mA]'
    x_label = 'Drain-Source Voltage ($V_{DS}$) [Volts]'
    legend_title = "Gate Drive"
else:
    y_label = 'Collector Current ($I_C$) [mA]'
    x_label = 'Collector-Emitter Voltage ($V_{CE}$) [Volts]'
    legend_title = "Base Drive"

# Setup the Figure
fig, ax = plt.subplots(figsize=(10, 6))
fig.canvas.manager.set_window_title(f'{COMP_NAME} Test Results')

ax.set_title(f'{COMP_NAME} Output Characteristics', fontsize=16, fontweight='bold')
ax.set_xlabel(x_label, fontsize=12)
ax.set_ylabel(y_label, fontsize=12)
ax.grid(True, linestyle="--", alpha=0.7)

# Pre-calculate axes limits so the graph doesn't jump around while drawing
ax.set_xlim(0, df['V_Sweep_Volts'].max() * 1.05)
ax.set_ylim(0, df['Current_mA'].max() * 1.1)

# Initialize empty lines for the animation
curves = df['Curve_Num'].unique()
lines = []
for curve in curves:
    # Create an empty line object for each curve step
    line, = ax.plot([], [], linewidth=2, label=f'Step {int(curve)}')
    lines.append(line)

ax.legend(title=legend_title)
plt.tight_layout()

# Find the maximum number of data points in any single curve to know how long to animate
max_points = df.groupby('Curve_Num').size().max()

def init():
    """Starts the graph completely empty."""
    for line in lines:
        line.set_data([], [])
    return lines

def update(frame):
    """Draws the data frame-by-frame (point-by-point)."""
    for i, curve in enumerate(curves):
        curve_data = df[df['Curve_Num'] == curve]
        
        # Slices the data array up to the current animation frame
        x_data = curve_data['V_Sweep_Volts'].iloc[:frame]
        y_data = curve_data['Current_mA'].iloc[:frame]
        
        lines[i].set_data(x_data, y_data)
    return lines

# The Animation Engine
# interval=15 controls the speed (15 milliseconds per frame). Lower is faster.
ani = animation.FuncAnimation(fig, update, frames=max_points + 1,
                              init_func=init, blit=True, interval=15, repeat=False)

plt.show()