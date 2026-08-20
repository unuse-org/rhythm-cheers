/**
 * ESP-NOW 加速度送信側（Receiver とコメント書式を揃えた版）
 * Device : M5StickC Plus2
 * Board  : m5stick-c (PlatformIO)
 *
 * 【シリアル出力フォーマット】
 * [Sender] X:0.123 Y:-0.456 Z:9.789  OK|FAIL
 *
 * 【手順】
 * 1. 先に Receiver を書き込み、シリアルモニタで AP MAC アドレスを確認する
 * 2. 下の RECEIVER_MAC を受信側の AP MAC に書き換える
 * 3. このスケッチを書き込む
 */

#include <Arduino.h>
#include <M5StickCPlus2.h>
#include <WiFi.h>
#include <esp_now.h>

// =============================================
// ★ 受信側の MAC アドレスをここに設定してください
// =============================================
static constexpr uint8_t RECEIVER_MAC[6] = {0x00, 0x4B, 0x12, 0xA0, 0x9A, 0x5D};

// =============================================
// 送受信共通データ構造体（Receiver と同じにすること）
// =============================================
typedef struct {
    float accX;
    float accY;
    float accZ;
} AccelData;

// =============================================
// グローバル変数
// =============================================
static AccelData      g_data;
static esp_now_peer_info_t g_peerInfo;
static volatile bool  g_sendSuccess = false;
static uint32_t       g_sendCount   = 0;

/**
 * @brief 送信結果コールバック。
 *
 * @param mac_addr 送信先 MAC アドレス（未使用）
 * @param status 送信ステータス
 */
void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status)
{
    g_sendSuccess = (status == ESP_NOW_SEND_SUCCESS);
}

// =============================================
// 画面描画
// =============================================
void drawDisplay()
{
    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setCursor(0, 0);
    M5.Lcd.setTextColor(CYAN, BLACK);
    M5.Lcd.println("== SENDER ==");

    M5.Lcd.setTextColor(WHITE, BLACK);
    M5.Lcd.printf("X:%7.3f\n", g_data.accX);
    M5.Lcd.printf("Y:%7.3f\n", g_data.accY);
    M5.Lcd.printf("Z:%7.3f\n", g_data.accZ);

    M5.Lcd.setTextColor(g_sendSuccess ? GREEN : RED, BLACK);
    M5.Lcd.printf("Send:%s #%lu\n",
                  g_sendSuccess ? " OK " : "FAIL",
                  g_sendCount);
}

// =============================================
// setup(): ハードウェア、WiFi、ESP-NOW を初期化
// =============================================
void setup()
{
    M5.begin();
    Serial.begin(115200);

    M5.Lcd.setRotation(3);
    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setTextColor(WHITE, BLACK);

    // --- WiFi ---
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();

    Serial.print("[Sender] My MAC: ");
    Serial.println(WiFi.macAddress());

    M5.Lcd.setCursor(0, 0);
    M5.Lcd.println("My MAC:");
    M5.Lcd.println(WiFi.macAddress());
    delay(2000);

    // --- ESP-NOW 初期化 ---
    if (esp_now_init() != ESP_OK) {
        Serial.println("[ERROR] ESP-NOW init failed");
        M5.Lcd.fillScreen(RED);
        M5.Lcd.println("ESP-NOW\nINIT\nFAILED");
        while (true) { delay(1000); }
    }
    esp_now_register_send_cb(onDataSent);

    // --- ピア登録 ---
    memset(&g_peerInfo, 0, sizeof(g_peerInfo));
    memcpy(g_peerInfo.peer_addr, RECEIVER_MAC, 6);
    g_peerInfo.channel = 0;
    g_peerInfo.encrypt = false;

    if (esp_now_add_peer(&g_peerInfo) != ESP_OK) {
        Serial.println("[ERROR] Failed to add peer");
        M5.Lcd.fillScreen(RED);
        M5.Lcd.println("PEER\nADD\nFAILED");
        while (true) { delay(1000); }
    }

    Serial.println("[Sender] Ready. Sending @ 10 Hz");
}

// =============================================
// loop(): 加速度取得・送信・表示更新
// =============================================
void loop()
{
    M5.update();

    // 加速度取得
    M5.Imu.getAccelData(&g_data.accX, &g_data.accY, &g_data.accZ);

    // 送信
    esp_err_t result = esp_now_send(RECEIVER_MAC,
                                    reinterpret_cast<uint8_t *>(&g_data),
                                    sizeof(g_data));
    if (result == ESP_OK) {
        g_sendCount++;
    }

    // シリアル出力（簡易フォーマット）
    Serial.printf("[Sender] X:%.3f Y:%.3f Z:%.3f  %s\n",
                  g_data.accX, g_data.accY, g_data.accZ,
                  g_sendSuccess ? "OK" : "FAIL");

    // 画面更新
    drawDisplay();

    delay(100); // 10 Hz
}