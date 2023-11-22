# catflap.esp32
Cat flap driven by Tasmota on ESP32

I had a "Cat mate elite" cat door that was non-functional, presumably due to some bad reed sensors. In any case, I didn't like the fact it required an ID tag. I also wasn't able to find any other basic cat door with a simple timer to unlock/lock. So I decided to mod this cat door instead.

The existing door uses a DC motor, worm drive and a LM393 sensor. I retained this design but needed to replace the LM393 with my own. Hopefully the photos make it clear how it works.

![PXL_20231105_054249425](https://github.com/arendst/Tasmota/assets/6404304/205e6ee0-664b-4a14-88ed-d85ea4a62fd5)
![PXL_20231105_054257797](https://github.com/arendst/Tasmota/assets/6404304/f5d31e28-b7dc-4fdd-b8af-6063c1340cfa)


Parts list

- ESP-C3-12F - Tasmota 32 c3 firmware
- 500R and 10k resistor x2
- Cat Mate Elite Cat Door
- LM393 Speed Sensor
- 3.3v regulator (HT7833)
- Capacitors; 105(1uF), 47uf
- 2N2222 transistor
- Motor driver (DRV8833)
- PCB board (7cmx5cm)

I had to do some modifications to the LM393 sensor to allow the IR sensor to be separate from the PCB.

As it is powered by 4 AA batteries, my goal was to keep power usage as low as possible. I used the 'enable/sleep' pin on the DRV8833 and activated the LMR393 via the 2N2222. (NB: I was also able to power the LM393 directly via the ESP32, but it's close/over the current limit).

![PXL_20231121_033213657](https://github.com/smhc/catflap.esp32/assets/6404304/2d50627d-0999-44dc-aba9-d612f8b53e8d)
![PXL_20231121_033148169](https://github.com/smhc/catflap.esp32/assets/6404304/c6ccdf3b-5b0b-404b-93b9-bd9bf1d453b7)


The motor driver code ramps up to full speed, then tapers down to minimum speed. While doing this it gets into a starting state (using LM393 sensor), then hits the brakes on the motor if it reaches the target state. It tries again if it can't reach the target state. It also handles aborting if it can't get into the correct state after a period of time.

The sleep timer code uses a hack to determine an appropriate interval to "deep sleep". This is because the current deep sleep functionality in Tasmota only allows entering a deep sleep on a scheduled interval, where the start and end time of the sleep cannot be easily controlled. This formula is:

```
firstwake = ((floor(current_timestamp / deepsleep_interval) + 1) * deepsleep_interval) + (deepsleep_interval * 0.05)
subsequent_wake = prevwake + deepsleep_interval
```

It is possible to "game" this implementation to sleep until any given time, within a few minutes or so. The sleep timer code accomplishes this in order to only wake twice a day - once to lock the door, and again to unlock. 
