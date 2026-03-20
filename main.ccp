#include <Arduino.h>
#include <SPI.h>
#include <MFRC522.h>
#include <BleKeyboard.h> // ESP32 BLE Keyboard (Bluedroid)

// =============================================================================
// KONFIGURACJA PINÓW (ESP32 DEVKIT v1)
// =============================================================================

// VSPI (sprzętowa magistrala SPI)
#define SCK_PIN 18
#define MISO_PIN 19
#define MOSI_PIN 23
#define SS_PIN 5   // MFRC522 SDA/SS
#define RST_PIN 22 // MFRC522 RST

// Waga na UART2
#define SCALE_RX_PIN 16 // RX2 (ESP32 odbiera)
#define SCALE_TX_PIN 17 // TX2 (ESP32 nadaje)

// LED (wbudowany na wielu DevKit v1)
#define LED_PIN 2

// =============================================================================
// OBIEKTY I ZMIENNE
// =============================================================================

MFRC522 mfrc522(SS_PIN, RST_PIN);
HardwareSerial scale(2);                               // Serial2
BleKeyboard bleKeyboard("POS_Mod_01", "Wekwejt", 100); // name, manufacturer, initial battery %

bool bleReady = false;          // zainicjalizowano BLE
unsigned long lastCardRead = 0; // antystukanie
unsigned long initTime = 0;     // start uptime

int cardsSent = 0;
int weightsSent = 0;

// =============================================================================
// PROTOTYPY
// =============================================================================
void handleRFID();
void handleScale();
void blinkLED(int times);
void sendDataViaBLE(const String &data);
bool containsFloat(const String &str);
void processScaleData();
void initBLE();
void printBLEStatus();
void testConnection();

// =============================================================================
// SETUP
// =============================================================================
void setup()
{
  Serial.begin(115200);
  delay(2000);
  initTime = millis();

  Serial.println();
  Serial.println("================================");
  Serial.println("===   POS BLE HID KEYBOARD   ===");
  Serial.println("===     Wekwejt Robotics     ===");
  Serial.println("================================");

  // LED
  pinMode(LED_PIN, OUTPUT);
  blinkLED(2);
  Serial.println("LED init done");

  // RFID
  Serial.println("Init SPI + RFID...");
  SPI.begin(SCK_PIN, MISO_PIN, MOSI_PIN, SS_PIN);
  mfrc522.PCD_Init();
  delay(200);

  byte version = mfrc522.PCD_ReadRegister(mfrc522.VersionReg);
  if (version != 0x00 && version != 0xFF)
  {
    Serial.print("RFID OK (v0x");
    Serial.print(version, HEX);
    Serial.println(")");
  }
  else
  {
    Serial.println("RFID ERROR – check wiring");
  }

  // Scale
  Serial.println("Init Scale (Serial2)...");
  scale.begin(9600, SERIAL_8N1, SCALE_RX_PIN, SCALE_TX_PIN);
  Serial.println("Scale UART init done");

  // BLE
  initBLE();

  Serial.println("================================");
  Serial.println("SYSTEM READY – pair 'POS_Keyboard' now");
  Serial.println("================================");

  blinkLED(3);
}

// =============================================================================
// BLE INIT
// =============================================================================
void initBLE()
{
  Serial.println();
  Serial.println("Init BLE Keyboard...");

  // Możesz zmienić nazwę dynamicznie, ale ustawiona w konstruktorze zwykle wystarcza.
  // bleKeyboard.setName("Harvest_Keyboard");
  // bleKeyboard.setDelay(10); // ms pomiędzy znakami (opcjonalnie)

  bleKeyboard.begin();
  delay(500);      // krótka stabilizacja
  bleReady = true; // Inicjowanie zakończone (nie oznacza połączenia!)

  Serial.println("BLE stack started. Waiting for host to connect...");
}

// =============================================================================
// LOOP
// =============================================================================
void loop()
{
  // Heartbeat co 30 s
  static unsigned long lastHeartbeat = 0;
  if (millis() - lastHeartbeat > 30000)
  {
    Serial.printf("\n[HB] %lus | Cards:%d | Weights:%d | Conn:%s\n",
                  (millis() - initTime) / 1000,
                  cardsSent,
                  weightsSent,
                  bleKeyboard.isConnected() ? "YES" : "NO");
    lastHeartbeat = millis();
  }

  handleRFID();
  handleScale();

  delay(20); // krótszy delay = responsywność
}

// =============================================================================
// OBSŁUGA RFID
// =============================================================================
void handleRFID()
{
  if (millis() - lastCardRead < 1000)
    return; // antybounce kart

  if (mfrc522.PICC_IsNewCardPresent() && mfrc522.PICC_ReadCardSerial())
  {
    String cardUID;
    for (byte i = 0; i < mfrc522.uid.size; i++)
    {
      if (mfrc522.uid.uidByte[i] < 0x10)
        cardUID += "0";
      cardUID += String(mfrc522.uid.uidByte[i], HEX);
    }
    cardUID.toUpperCase();

    Serial.print("RFID: ");
    Serial.println(cardUID);

    if (bleReady)
    {
      String data = "CARD:" + cardUID;
      sendDataViaBLE(cardUID);
      cardsSent++;
      Serial.printf("Card sent via BLE (#%d)\n", cardsSent);
    }
    else
    {
      Serial.println("BLE not ready – card skipped");
    }

    mfrc522.PICC_HaltA();
    mfrc522.PCD_StopCrypto1();
    lastCardRead = millis();
    blinkLED(1);
  }
}

// =============================================================================
// OBSŁUGA WAGI
// =============================================================================
void handleScale()
{
  if (!scale.available())
    return;

  String data = scale.readStringUntil('\n');
  data.trim();
  if (data.length() > 0)
  {
    Serial.print("Scale raw: ");
    Serial.println(data);
  }

  // Rozpoznaj marker początku bloku wagi
  if (data.indexOf("====") != -1 || data.indexOf("===") != -1)
  {
    Serial.println("Parsing scale block...");
    processScaleData();
  }
}

void processScaleData()
{
  for (int i = 0; i < 8; i++)
  {
    if (!scale.available())
    {
      delay(50);
      continue;
    }

    String line = scale.readStringUntil('\n');
    line.trim();
    if (line.length() > 0)
    {
      Serial.printf("Line %d: %s\n", i, line.c_str());

      if (line.indexOf(' ') > 0 && containsFloat(line))
      {
        int spacePos = line.indexOf(' ');
        String weightStr = line.substring(0, spacePos);
        float weight = weightStr.toFloat();

        if (weight > 0.001f && weight < 50.0f)
        {
          Serial.printf("Weight: %.3f kg\n", weight);

          if (bleReady)
          {
            String data = String(weight, 3) + "kg";
            sendDataViaBLE(data);
            weightsSent++;
            Serial.printf("Weight sent via BLE (#%d)\n", weightsSent);
          }
          else
          {
            Serial.println("BLE not ready – weight skipped");
          }

          blinkLED(2);
          return; // zakończ po pierwszym sensownym odczycie
        }
      }
    }
  }
}

// =============================================================================
// BLE OUTPUT
// =============================================================================
void sendDataViaBLE(const String &data)
{
  if (!bleReady)
  {
    Serial.print("BLE not initialized: ");
    Serial.println(data);
    return;
  }

  if (!bleKeyboard.isConnected())
  {
    Serial.print("BLE not connected – skip: ");
    Serial.println(data);
    return;
  }

  Serial.print("BLE → ");
  Serial.println(data);
  bleKeyboard.print(data);
  bleKeyboard.write(KEY_RETURN);
  delay(5); // małe odsapnięcie, by host przetworzył znak
}

// =============================================================================
// HELPERY
// =============================================================================
bool containsFloat(const String &str)
{
  for (int i = 0; i < str.length(); i++)
  {
    if (isDigit(str[i]))
      return true;
  }
  return false;
}

void blinkLED(int times)
{
  for (int i = 0; i < times; i++)
  {
    digitalWrite(LED_PIN, HIGH);
    delay(150);
    digitalWrite(LED_PIN, LOW);
    delay(150);
  }
}

// =============================================================================
// DIAGNOSTYKA (manualnie wywoływane np. z Serial Monitor)
// =============================================================================
void printBLEStatus()
{
  Serial.println();
  Serial.println("=== BLE STATUS ===");
  Serial.printf("BLE Ready: %s\n", bleReady ? "YES" : "NO");
  Serial.printf("BLE Connected: %s\n", bleKeyboard.isConnected() ? "YES" : "NO");
  Serial.printf("Cards sent: %d\n", cardsSent);
  Serial.printf("Weights sent: %d\n", weightsSent);
  Serial.printf("Uptime: %lus\n", (millis() - initTime) / 1000);
  Serial.println("==================");
}

void testConnection()
{
  Serial.println("Testing BLE connection...");
  if (!bleReady)
  {
    Serial.println("BLE not ready");
    return;
  }
  if (!bleKeyboard.isConnected())
  {
    Serial.println("BLE not connected");
    return;
  }
  bleKeyboard.print("TEST ");
  bleKeyboard.print(String(millis() / 1000));
  bleKeyboard.write(KEY_RETURN);
  Serial.println("Test sent");
}
