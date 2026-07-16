import machine
import sys
import select
import shrike

fpga_pwr = machine.Pin(12, machine.Pin.OUT)
fpga_en = machine.Pin(13, machine.Pin.OUT)
fpga_ss = machine.Pin(1, machine.Pin.OUT)

fpga_pwr.value(1)
fpga_ss.value(1)                           
fpga_en.value(0)                                  
for _ in range(1000):
    pass
fpga_en.value(1)               

data_pins = [machine.Pin(i) for i in (0, 1, 2, 3)]
strobe_pin = machine.Pin(15, machine.Pin.OUT)
valid_pin = machine.Pin(14, machine.Pin.IN)

strobe_pin.value(0)

try:
    shrike.SPI.deinit()
except Exception:
    pass

def set_data_out():
    machine.mem32[0xd0000024] = 0x0F

def set_data_in():
    machine.mem32[0xd0000028] = 0x0F

def send_12bit(adc_value):
    set_data_out()
    
    machine.mem32[0xd0000018] = 0x0F
    machine.mem32[0xd0000014] = (adc_value & 0x0F) | (1 << 15)
    
    machine.mem32[0xd0000018] = 0x0F | (1 << 15)
    machine.mem32[0xd0000014] = (adc_value >> 4) & 0x0F
    
    machine.mem32[0xd0000018] = 0x0F
    machine.mem32[0xd0000014] = ((adc_value >> 8) & 0x0F) | (1 << 15)
    
    set_data_in()

def read_nibble():
    return machine.mem32[0xd0000004] & 0x0F

def wait_for_valid(level):
    timeout = 50000
    while ((machine.mem32[0xd0000004] >> 14) & 1) != level and timeout > 0:
        timeout -= 1
    return timeout > 0

def read_12bit_back():
    if not wait_for_valid(1):
        return None
    low = read_nibble()
    
    if not wait_for_valid(0):
        return None
    mid = read_nibble()
    
    if not wait_for_valid(1):
        return None
    high = read_nibble()
    
    wait_for_valid(0)
    
    return (high << 8) | (mid << 4) | low

poll = select.poll()
poll.register(sys.stdin, select.POLLIN)

while True:
    events = poll.poll(100)
    if events:
        line = sys.stdin.readline()
        if line:
            try:
                adc_value = int(line.strip(), 16)
                
                send_12bit(adc_value)
                
                calib_val = read_12bit_back()
                
                if calib_val is not None:
                    print(hex(calib_val))
                else:
                    print("ERROR")
            except Exception:
                print("PARSE_ERROR")
