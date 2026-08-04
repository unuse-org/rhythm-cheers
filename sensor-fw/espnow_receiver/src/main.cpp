/**
 * ESP-NOW 加速度受信側（複数Sender対応）
 * Device : M5StickC Plus2
 * Board  : m5stick-c (PlatformIO)
 *
 * 【シリアル出力フォーマット】
 * {"id":1,"mac":"AA:BB:CC:DD:EE:FF","x":0.1234,"y":-0.4567,"z":9.7891,"count":42}
 *
 * 【手順】
 * 1. このスケッチを書き込む
 * 2. 起動直後の画面 or シリアルモニタで AP MAC アドレスを確認する
 * 3. 各 Sender の RECEIVER_MAC にその AP MAC を設定して書き込む
 */

#include <Arduino.h>
#include <M5StickCPlus2.h>
#include <WiFi.h>
#include <esp_now.h>

// =============================================
// 設定
// =============================================
static constexpr uint8_t  MAX_SENDERS    = 8;
static constexpr uint32_t DISPLAY_MS     = 50;   // 画面更新間隔 [ms]

// =============================================
// 送受信共通データ構造体（Sender と同じにすること）
// =============================================
typedef struct {
    float accX;
    float accY;
    float accZ;
} AccelData;

// =============================================
// Sender 管理テーブル
// =============================================
typedef struct {
    uint8_t   mac[6];
    bool      active;
    uint32_t  recvCount;
    AccelData latest;
} SenderEntry;

static SenderEntry g_senders[MAX_SENDERS] = {};
static uint8_t     g_senderCount = 0;

// =============================================
// 受信キュー（コールバック → loop 間の受け渡し）
// =============================================
typedef struct {
    uint8_t   mac[6];
    AccelData data;
    bool      valid;
} RecvQueue;

static volatile RecvQueue g_queue = {};

// 表示用
static uint8_t   g_dispSender  = 0;     // 現在表示中の Sender インデックス
static uint32_t  g_lastDisplay = 0;

// =============================================
// ユーティリティ
// =============================================
String macToStr(const uint8_t *mac)
{
    char buf[18];
    snprintf(buf, sizeof(buf), "%02X:%02X:%02X:%02X:%02X:%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    return String(buf);
}

bool macEquals(const uint8_t *a, const uint8_t *b)
{
    return memcmp(a, b, 6) == 0;
}

int findOrAddSender(const uint8_t *mac)
{
    for (int i = 0; i < g_senderCount; i++) {
        if (macEquals(g_senders[i].mac, mac)) return i;
    }
    if (g_senderCount >= MAX_SENDERS) return -1;
    int idx = g_senderCount++;
    memcpy(g_senders[idx].mac, mac, 6);
    g_senders[idx].active    = true;
    g_senders[idx].recvCount = 0;
    Serial.printf("[Receiver] New sender #%d: %s\n", idx + 1, macToStr(mac).c_str());
    return idx;
}

// =============================================
// ESP-NOW コールバック
// arduino-esp32 2.x / espressif32@6.x 旧 API
// =============================================
void onDataReceived(const uint8_t *mac_addr, const uint8_t *data, int len)
{
    if (len != sizeof(AccelData)) return;
    if (g_queue.valid) return;
    memcpy((void *)g_queue.mac,   mac_addr, 6);
    memcpy((void *)&g_queue.data, data,     sizeof(AccelData));
    g_queue.valid = true;
}

// =============================================
// JSON シリアル出力
// =============================================
void sendJson(int idx)
{
    SenderEntry &s = g_senders[idx];
    Serial.printf(
        "{\"id\":%d,\"mac\":\"%s\",\"x\":%.4f,\"y\":%.4f,\"z\":%.4f,\"count\":%lu}\n",
        idx + 1,
        macToStr(s.mac).c_str(),
        s.latest.accX,
        s.latest.accY,
        s.latest.accZ,
        s.recvCount
    );
}

// =============================================
// LCD 画面描画
// =============================================
// Sender が 0 台のとき：待機画面
void drawWaiting()
{
    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setTextColor(YELLOW, BLACK);
    M5.Lcd.setCursor(0, 0);
    M5.Lcd.println("== RECEIVER ==");
    M5.Lcd.setTextColor(WHITE, BLACK);
    M5.Lcd.println("Waiting...");
    M5.Lcd.setTextSize(1);
    M5.Lcd.setTextColor(LIGHTGREY, BLACK);
    M5.Lcd.printf("AP MAC:\n%s", WiFi.softAPmacAddress().c_str());
}

// Sender データ表示（1台分）
void drawSender(uint8_t idx)
{
    if (idx >= g_senderCount) return;
    SenderEntry &s = g_senders[idx];

    // Sender ごとのヘッダ色
    const uint16_t headerColors[] = {GREEN, RED, YELLOW, CYAN, MAGENTA};
    uint16_t hColor = (idx < 5) ? headerColors[idx] : WHITE;

    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setCursor(0, 0);
    M5.Lcd.setTextColor(hColor, BLACK);
    M5.Lcd.printf("Sender #%d/%d\n", idx + 1, g_senderCount);

    M5.Lcd.setTextColor(WHITE, BLACK);
    M5.Lcd.printf("X:%7.3f\n", s.latest.accX);
    M5.Lcd.printf("Y:%7.3f\n", s.latest.accY);
    M5.Lcd.printf("Z:%7.3f\n", s.latest.accZ);

    M5.Lcd.setTextColor(GREEN, BLACK);
    M5.Lcd.printf("#%lu\n", s.recvCount);

    M5.Lcd.setTextSize(1);
    M5.Lcd.setTextColor(LIGHTGREY, BLACK);
    M5.Lcd.printf("%s", macToStr(s.mac).c_str());
}

// =============================================
// setup
// =============================================
void setup()
{
    M5.begin();
    Serial.begin(115200);
    delay(300);

    M5.Lcd.setRotation(3);
    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setTextColor(WHITE, BLACK);

    Serial.println("=== ESP-NOW Receiver (M5StickC Plus2) ===");

    // WiFi AP モードで起動（ESP-NOW 安定動作のため）
    WiFi.mode(WIFI_AP);
    WiFi.softAP("ESPNOW-RX", nullptr, 1, true);  // 隠し AP
    delay(200);

    String apMac  = WiFi.softAPmacAddress();
    String staMac = WiFi.macAddress();
    Serial.print("[Receiver] AP  MAC: "); Serial.println(apMac);
    Serial.print("[Receiver] STA MAC: "); Serial.println(staMac);
    Serial.println("[Receiver] ★ Set AP MAC to RECEIVER_MAC in each Sender ★");

    // 起動時に MAC を画面表示（3秒）
    M5.Lcd.setCursor(0, 0);
    M5.Lcd.setTextColor(YELLOW, BLACK);
    M5.Lcd.println("AP MAC:");
    M5.Lcd.setTextSize(1);
    M5.Lcd.setTextColor(WHITE, BLACK);
    M5.Lcd.println(apMac);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setTextColor(CYAN, BLACK);
    M5.Lcd.println("\nSet to\nSenders!");
    delay(3000);

    // ESP-NOW 初期化
    if (esp_now_init() != ESP_OK) {
        Serial.println("[ERROR] ESP-NOW init failed!");
        M5.Lcd.fillScreen(RED);
        M5.Lcd.setCursor(0, 0);
        M5.Lcd.println("ESP-NOW\nFAILED");
        while (true) { delay(1000); }
    }

    esp_now_register_recv_cb(onDataReceived);

    Serial.println("[Receiver] Ready.");
    drawWaiting();
}

// =============================================
// loop
// =============================================
void loop()
{
    M5.update();

    // ボタンA：次の Sender に切り替え
    if (M5.BtnA.wasPressed() && g_senderCount > 1) {
        g_dispSender = (g_dispSender + 1) % g_senderCount;
        drawSender(g_dispSender);
    }

    // 受信キューの処理
    if (g_queue.valid) {
        uint8_t   mac[6];
        AccelData data;
        memcpy(mac,   (void *)g_queue.mac,   6);
        memcpy(&data, (void *)&g_queue.data, sizeof(AccelData));
        g_queue.valid = false;

        int idx = findOrAddSender(mac);
        if (idx >= 0) {
            g_senders[idx].latest = data;
            g_senders[idx].recvCount++;

            // JSON シリアル出力
            sendJson(idx);

            // 現在表示中の Sender なら画面更新（一定間隔で）
            uint32_t now = millis();
            if ((uint8_t)idx == g_dispSender && now - g_lastDisplay >= DISPLAY_MS) {
                drawSender(g_dispSender);
                g_lastDisplay = now;
            }
        }
    }

    delay(1);
}