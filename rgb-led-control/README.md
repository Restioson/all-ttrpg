# rgb-led-control

Project to control RGB LEDs from an ESP32 microcontroller board. The Rust portion (initially generated with the rust
ESP32 template) runs on the ESP32 itself, while [`heartbeat_client.html`](heartbeat_client.html) is a standalone HTML+CSS+JS client that
needs no server. Tested and works on latest Chrome on Windows 11, and also on latest Firefox on Linux.

## heartbeat

The only implemented part of rgb-led-control is the heartbeat program. This causes the LED to have a heartbeat effect,
with configurable HSL colour (~mostly colour corrected) and BPM. It also plays synchronised sound effects through the
browser.


Minis from various sources - heart from
[SF3DPrints on MakerWorld](https://makerworld.com/en/models/229829-anatomically-accurate-heart)

<video src="https://github.com/user-attachments/assets/bc340950-369f-4721-ab5e-caf0e4af5077"/>
