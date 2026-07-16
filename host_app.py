import numpy as np
import serial
import time

SERIAL_PORT = '/dev/cu.usbmodem101' 
BAUD_RATE = 115200

try:
    ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0.5)
    ser.reset_input_buffer()
    time.sleep(0.1)
    ser.reset_input_buffer()
    print("Streaming data pipeline open to Vicharak RP2040...")
except Exception as e:
    print(f"Error opening port: {e}")
    exit()

t = np.linspace(0, 1, 200)
ideal_signal = np.sin(2 * np.pi * 50 * t)
distorted = ideal_signal + 0.15 * (ideal_signal ** 2) - 0.08 * (ideal_signal ** 3)
adc_codes = ((np.clip(distorted, -1.0, 1.0) + 1.0) * 2047.5).astype(np.uint16)

print(f"{'Index':<6} | {'Raw ADC Code':<14} | {'Calibrated Output':<18}")
print("-" * 46)

for i, code in enumerate(adc_codes):
    ser.write(f"{code:03X}\n".encode())
    
    time.sleep(0.002) 
    
    line = ser.readline()
    if line:
        resp_str = line.decode().strip()
        if resp_str in ("ERROR", "PARSE_ERROR") or not resp_str:
            print(f"{i:<6} | {code:<14} | {resp_str:<18}")
        else:
            try:
                calib_val = int(resp_str, 16)
                print(f"{i:<6} | {code:<14} | {calib_val:<18}")
            except Exception:
                print(f"{i:<6} | {code:<14} | INVALID ({resp_str})")
    else:
        print(f"{i:<6} | {code:<14} | ERROR (No Response)")

ser.close()
print("Data stream injection and readback complete.")
