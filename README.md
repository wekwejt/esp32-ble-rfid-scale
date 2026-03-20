# ESP32 BLE HID Keyboard + RFID + Scale Integration

Firmware for ESP32 DevKit v1 acting as a wireless BLE HID keyboard.  
Reads RFID card UIDs (MFRC522) and weight measurements (CAS scale via UART) and sends them as keystrokes to any connected host (PC, tablet, POS terminal).

---

## Use Case

Automated data entry in industrial/warehouse environments – scanning an RFID card or placing goods on the scale instantly "types" the result into any active input field on the host, without any driver or software installation.

---

## Hardware

| Component | Interface | Pins |
|---|---|---|
| ESP32 C3 | – | – |
| MFRC522 RFID Reader | SPI (VSPI) | SCK=18, MISO=19, MOSI=23, SS=5, RST=22 |
| CAS Scale | UART2 | RX=16, TX=17, 9600 baud |
| Status LED | GPIO | 2 (built-in) |

---

## Features

- **BLE HID Keyboard** – pairs with any BLE host, no drivers required
- **RFID reading** – sends card UID as text + Enter keystroke
- **Scale reading** – parses weight data block from CAS scale, sends `X.XXXkg` + Enter
- **Anti-bounce** – 1s lockout after card read
- **Heartbeat log** – serial status every 30s (uptime, counters, BLE state)
- **LED feedback** – blinks on card read (1×) and weight send (2×)

---

## BLE Device Info

| Parameter | Value |
|---|---|
| Device name | `POS_Mod_01` |
| Manufacturer | `XXX` |
| Profile | HID Keyboard (Bluedroid stack) |

---

## Build & Flash

**PlatformIO:**
```ini
[env:esp32c3]
platform = espressif32
board = esp32dev
framework = arduino
lib_deps = 
	miguelbalboa/MFRC522@^1.4.12
	T-vK/ESP32 BLE Keyboard @ ^0.3.2               ; Bluedroid BLE HID klawiatura
monitor_speed = 115200
upload_speed = 921600
build_flags = 
  -D CORE_DEBUG_LEVEL=1

```

---

## Serial Monitor Output (115200 baud)

```
=== POS BLE HID KEYBOARD ===
RFID OK (v0x92)
BLE stack started. Waiting for host to connect...
RFID: A3F209CC
BLE → A3F209CC
Scale raw: 1.250 kg
Weight: 1.250 kg
BLE → 1.250kg
[HB] 30s | Cards:2 | Weights:1 | Conn:YES
```

---

## Project Structure

```
├── src/
│   └── main.cpp       # Full firmware source
├── platformio.ini     # PlatformIO config (optional)
└── README.md
```

---

## License

© 2024 ladybit.pl. All rights reserved.

Personal and educational use permitted.  
Commercial use, resale or integration into commercial products requires written permission from the author.  
Contact: ladybit.pl
