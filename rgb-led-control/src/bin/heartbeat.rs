#![no_std]
#![no_main]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]
#![deny(clippy::large_stack_frames)]
extern crate alloc;

use alloc::string::String;
use anyhow::{anyhow, Error, Result};
use micromath::F32Ext;
use alloc::vec;
use alloc::vec::Vec;
use core::fmt::{Debug, Formatter};
use esp_hal::{
    Async,
    uart::{AtCmdConfig, Config, RxConfig, Uart, UartRx, UartTx},
};

use embedded_hal::pwm::SetDutyCycle;
use embassy_sync::{blocking_mutex::raw::NoopRawMutex};
use embassy_executor::Spawner;
use embassy_futures::join::join3;
use embassy_sync::rwlock::RwLock;
use esp_backtrace as _;
use embassy_time::{Duration, Instant, Ticker, Timer, WithTimeout};
use esp_hal::clock::CpuClock;
use esp_hal::gpio::{DriveMode, Level, Output, OutputConfig};
use esp_hal::ledc::{channel, timer, LSGlobalClkSource, Ledc, LowSpeed};
use esp_hal::ledc::channel::{Channel, ChannelIFace, FadeError, Number};
use esp_hal::ledc::timer::TimerIFace;
use esp_hal::peripherals::LEDC;
use esp_hal::time::Rate;
use esp_hal::timer::timg::TimerGroup;
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use static_cell::StaticCell;

// This creates a default app-descriptor required by the esp-idf bootloader.
// For more information see: <https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/app_image_format.html#application-description>
esp_bootloader_esp_idf::esp_app_desc!();

#[allow(
    clippy::large_stack_frames,
    reason = "it's not unusual to allocate larger buffers etc. in main"
)]
#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    real_main(spawner).await
}

#[derive(Deserialize, Serialize, Debug, Clone)]
struct Instructions {
    stages: Vec<State>,
}

impl Default for Instructions {
    fn default() -> Self {
        Instructions {
            stages: vec![
                State {
                    length_ms: 150,
                    led: LedControl::Lerp {
                        start: Color::from_rgb(10, 0, 0),
                        end: Color::from_rgb(255, 0, 0),
                    },
                },
                State {
                    length_ms: 150,
                    led: LedControl::Lerp {
                        start: Color::from_rgb(255, 0, 0),
                        end: Color::from_rgb(255 / 5, 0, 0),
                    },
                },
                State {
                    length_ms: 1300,
                    led: LedControl::Lerp {
                        start: Color::from_rgb(255 / 5, 0, 0),
                        end: Color::from_rgb(10, 0, 0),
                    },
                },
                State {
                    length_ms: 100,
                    led: LedControl::Constant(Color::from_rgb(10, 0, 0))
                },
            ]
        }
    }
}

#[derive(Deserialize, Serialize, Debug, Copy, Clone)]
struct State {
    length_ms: u64,
    led: LedControl,
}

#[derive(Deserialize, Serialize, Debug, Copy, Clone)]
enum LedControl {
    Constant(Color),
    Lerp {
        start: Color,
        end: Color,
    }
}

trait AnyhowResultExt<T> {
    fn hardware(self) -> Result<T>;
    fn hw(self) -> Result<T> where Self: Sized {
        self.hardware()
    }
}

impl<T, E> AnyhowResultExt<T> for Result<T, E> where E: Debug {
    fn hardware(self) -> Result<T> {
        self.map_err(|e| anyhow!("Hardware error: {e:?}"))
    }
}


impl State {
    async fn fade(&self, channel: &mut Channel<'_, LowSpeed>, start: u32, end: u32) -> Result<()> {
        let start = 255 - start;
        let end = 255 - end;

        let start_pct = (start as f32 / 255.0 * 100.0).round() as u8;
        let end_pct = (end as f32 / 255.0 * 100.0).round() as u8;
        if end_pct.abs_diff(start_pct) > 0 {
            match channel.start_duty_fade(start_pct, end_pct, self.length_ms as u16) {
                // Fall back to stepping
                Ok(_) => {
                    Timer::after(Duration::from_millis(self.length_ms)).await;
                    Ok(())
                },
                Err(channel::Error::Fade(FadeError::Duration)) => {
                    let start_t = Instant::now();

                    let mut ticker = Ticker::every(Duration::from_millis(8));

                    let fade = async {
                        loop {
                            let now = Instant::now();
                            let elapsed_ms = (now - start_t).as_millis();
                            let progress = elapsed_ms as f32 / self.length_ms as f32;
                            let coeff = progress;

                            let current = (start as f32 * (1.0 - coeff)) + (end as f32 * coeff);
                            let max_duty = channel.max_duty_cycle();
                            let current_duty = (current / 255.0 * max_duty as f32).round() as u16;
                            channel.set_duty_cycle(current_duty).hw()?;
                            ticker.next().await;
                        }
                    };

                    match fade.with_deadline(start_t + Duration::from_millis(self.length_ms)).await {
                        Ok(Ok(())) | Err(_) => Ok(()),
                        Ok(e) => e,
                    }
                },
                Err(e) => Err(e).hw(),
            }
        } else {
            channel.set_duty_cycle_fraction(end as u16, 255).hw()?;
            Timer::after(Duration::from_millis(self.length_ms)).await;
            Ok(())
        }
    }

    async fn execute(&self, r: &mut Channel<'_, LowSpeed>, g: &mut Channel<'_, LowSpeed>, b: &mut Channel<'_, LowSpeed>) -> Result<()> {
        let set = |chan: &mut Channel<LowSpeed>, c| {
            chan.set_duty_cycle_fraction(255 - (c as u16), 255).hw()?;
            Ok::<(), Error>(())
        };

        match self.led {
            LedControl::Constant(c) => {
                set(r, c.r())?;
                set(g, c.g())?;
                set(b, c.b())?;
                Timer::after(Duration::from_millis(self.length_ms)).await;
            }
            LedControl::Lerp { start, end } => {
                let (res1, res2, res3) = join3(
                    self.fade(r, start.r(), end.r()),
                    self.fade(g, start.g(), end.g()),
                    self.fade(b, start.b(), end.b()),
                ).await;

                res1?;
                res2?;
                res3?;
            }
        }

        Ok(())
    }
}

#[derive(Deserialize, Serialize, Copy, Clone)]
struct Color(u32);

impl Color {
    fn from_rgb(r: u8, g: u8, b: u8) -> Self {
        Color(((r as u32) << 16) + ((g as u32) << 8) + b as u32)
    }
}

impl Debug for Color {
    fn fmt(&self, f: &mut Formatter<'_>) -> core::fmt::Result {
        write!(f, "Color(R: {}, G: {}, B: {})", self.0 >> 16 & 0xff, self.0 >> 8 & 0xff, self.0 & 0xff)
    }
}

impl Color {
    fn r(&self) -> u32 {
        self.0 >> 16 & 0xff
    }

    fn g(&self) -> u32 {
        (self.0 >> 8) & 0xff
    }

    fn b(&self) -> u32 {
        self.0 & 0xff
    }
}

// We have a different main function here since RustRover does not allow auto-imports from the
// #[esp_rtos::main]-annotated main() function for whatever reason. So, this is a workaround.
async fn real_main(spawner: Spawner) -> ! {
    // generator version: 1.3.0
    // generator parameters: --chip esp32 -o esp32-wroom-32d -o unstable-hal -o alloc -o wifi -o ble-bleps -o embassy -o stack-smashing-protection -o esp-backtrace -o log -o esp

    esp_println::logger::init_logger_from_env();

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 98768);
    // COEX needs more RAM - so we've added some more
    esp_alloc::heap_allocator!(size: 64 * 1024);


    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    // The following pins are used to bootstrap the chip. They are available
    // for use, but check the datasheet of the module for more information on them.
    // - GPIO0
    // - GPIO2
    // - GPIO5
    // - GPIO12
    // - GPIO15
    // These GPIO pins are in use by some feature of the module and should not be used.
    let _ = peripherals.GPIO6;
    let _ = peripherals.GPIO7;
    let _ = peripherals.GPIO8;
    let _ = peripherals.GPIO9;
    let _ = peripherals.GPIO10;
    let _ = peripherals.GPIO11;
    let _ = peripherals.GPIO16;
    let _ = peripherals.GPIO20;

    // Default pins for Uart communication
    let (tx_pin, rx_pin) = (peripherals.GPIO1, peripherals.GPIO3);

    let config = Config::default()
        .with_rx(RxConfig::default().with_fifo_full_threshold(READ_BUF_SIZE as u16));

    let mut uart0 = Uart::new(peripherals.UART0, config)
        .unwrap()
        .with_tx(tx_pin)
        .with_rx(rx_pin)
        .into_async();
    uart0.set_at_cmd(AtCmdConfig::default().with_cmd_char(AT_CMD));

    let (rx, tx) = uart0.split();

    static INSTRUCTIONS: StaticCell<RwLock<NoopRawMutex, Instructions>> = StaticCell::new();
    let instructions = &*INSTRUCTIONS.init(RwLock::new(Instructions::default()));

    spawner.spawn(reader(rx, &instructions).unwrap());
    spawner.spawn(writer(tx).unwrap());

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    let sw_interrupt =
        esp_hal::interrupt::software::SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timg0.timer0, sw_interrupt.software_interrupt0);

    info!("Embassy initialized!");

    let mut ledc = unsafe { Ledc::new(LEDC::steal()) };
    ledc.set_global_slow_clock(LSGlobalClkSource::APBClk);

    let mut lstimer0 = ledc.timer::<LowSpeed>(timer::Number::Timer0);
    lstimer0
        .configure(timer::config::Config {
            duty: timer::config::Duty::Duty8Bit,
            clock_source: timer::LSClockSource::APBClk,
            frequency: Rate::from_khz(24),
        })
        .unwrap();

    let led_r = Output::new(peripherals.GPIO27, Level::Low, OutputConfig::default());
    let led_g = Output::new(peripherals.GPIO25, Level::Low, OutputConfig::default());
    let led_b = Output::new(peripherals.GPIO26, Level::Low, OutputConfig::default());
    let led_r2 = Output::new(peripherals.GPIO2, Level::Low, OutputConfig::default());
    let led_g2 = Output::new(peripherals.GPIO9, Level::Low, OutputConfig::default());
    let led_b2 = Output::new(peripherals.GPIO5, Level::Low, OutputConfig::default());

    macro_rules! init_channel {
        (let mut $name:ident = ($number:expr, $pin:expr)) => {
            let mut $name = ledc.channel($number, $pin);
            $name
                .configure(channel::config::Config {
                    timer: &lstimer0,
                    duty_pct: 100,
                    drive_mode: DriveMode::PushPull,
                })
                .unwrap();
        };
    }

    init_channel!(let mut channel_r = (Number::Channel0, led_r));
    init_channel!(let mut channel_g = (Number::Channel1, led_g));
    init_channel!(let mut channel_b = (Number::Channel2, led_b));

    init_channel!(let mut channel_r2 = (Number::Channel0, led_r2));
    init_channel!(let mut channel_g2 = (Number::Channel1, led_g2));
    init_channel!(let mut channel_b2 = (Number::Channel2, led_b2));

    loop {
        let x = async {
            // info!("{}", serde_json_core::to_string::<_, {1024 * 4}>(&*instructions.read().await).map_err(|e| anyhow!("Json error: {e:?}"))?);

            let stages = instructions.read().await.stages.clone();
            for (i, state) in stages.iter().enumerate() {
                info!("{i}: {state:?}");

                let res = embassy_futures::join::join(
                    state.execute(&mut channel_r, &mut channel_g, &mut channel_b),
                    state.execute(&mut channel_r2, &mut channel_g2, &mut channel_b2)
                ).with_timeout(Duration::from_millis(state.length_ms)).await;

                match res {
                    Ok((res_a, res_b)) => (res_a?, res_b?),
                    Err(_) => ((), ()),
                };
            }

            Ok(())
        };

        let res: Result<()> = x.await;
        match res {
            Ok(_) => (),
            Err(e) => error!("{:?}", e),
        }
    }

    // for inspiration have a look at the examples at https://github.com/esp-rs/esp-hal/tree/esp-hal-v1.1.0/examples

}

#[embassy_executor::task]
async fn writer(mut tx: UartTx<'static, Async>) {
    embedded_io_async::Write::write(
        &mut tx,
        b"Hello async serial. Enter something ended with EOT (CTRL-D).\r\n",
    )
        .await
        .unwrap();
    embedded_io_async::Write::flush(&mut tx).await.unwrap();
}

const AT_CMD: u8 = 0x04;
const READ_BUF_SIZE: usize = 64;

#[embassy_executor::task]
async fn reader(mut rx: UartRx<'static, Async>, instructions: &'static RwLock<NoopRawMutex, Instructions>) {
    const MAX_BUFFER_SIZE: usize = 10 * READ_BUF_SIZE + 16;

    let mut rbuf: [u8; MAX_BUFFER_SIZE] = [0u8; MAX_BUFFER_SIZE];
    let mut offset = 0;
    loop {
        let r = embedded_io_async::Read::read(&mut rx, &mut rbuf[offset..]).await;
        match r {
            Ok(len) => {
                offset += len;

                info!("Recv: {}", String::from_utf8_lossy(&rbuf[..offset]));

                if let Some(end) = rbuf.iter().take(offset).position(|c| *c == b'\n') {
                    offset = end;

                    let mut lock = instructions.write().await;
                    match serde_json_core::from_slice(&rbuf[..offset + 1]) {
                        Ok(dat) => *lock = dat.0,
                        Err(e) => warn!("{e:?}"),
                    }

                    offset = 0;
                    rbuf = [0u8; MAX_BUFFER_SIZE];
                }

            }
            Err(e) => warn!("RX Error: {:?}", e),
        }
    }
}