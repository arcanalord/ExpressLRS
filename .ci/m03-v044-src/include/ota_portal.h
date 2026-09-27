#pragma once
#include <Arduino.h>
namespace mm::ota {
void begin(const String& nodeId);
void start();
void stop();
void loop();
bool active();
String ssid();
}
