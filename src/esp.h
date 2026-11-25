// esp.h - overlay entry points.
#pragma once

void esp_start(void);
void esp_set_visible(bool visible);
bool esp_is_visible(void);
// Called once per frame by the menu so aim data and drawing stay in sync.
void esp_tick(void);
