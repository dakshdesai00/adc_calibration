# ML-Driven Digital Calibration for High-Speed Data Converters

This project implements a digital calibration engine to correct non-linear distortions in high-speed Analog-to-Digital Converters (ADCs). In high-speed mixed-signal front-ends, manufacturing variances, aging, and thermal drift introduce integral non-linearity (INL) and differential non-linearity (DNL), causing harmonic distortions that degrade the signal-to-noise and distortion ratio (SNDR). 

Instead of deploying large, resource-intensive Look-Up Tables (LUTs) in hardware, this project implements a real-time, resource-optimized polynomial calibration engine directly inside an FPGA fabric to linearize the raw digitizer output.

---

## Detailed ADC Distortion and Modeling

High-speed ADCs suffer from static and dynamic non-linearities:
*   **Differential Non-Linearity (DNL)**: The deviation of an actual analog step width from the ideal value of 1 LSB.
*   **Integral Non-Linearity (INL)**: The cumulative deviation of the transfer function from a straight line.
*   **Harmonic Distortion**: INL and DNL introduce second- and third-order harmonics that pollute the frequency spectrum.

This system injects non-linear distortions mathematically to simulate these effects:
$$V_{distorted} = V_{ideal} + 0.15 \cdot V_{ideal}^2 - 0.08 \cdot V_{ideal}^3$$

The FPGA corrects these errors by executing a real-time polynomial regression model:
$$y = w_0 + w_1 \cdot x + w_2 \cdot x^2 + w_3 \cdot x^3$$
where $x$ is the zero-centered input ($x = \text{raw\_adc} - 2048$).

---

## Summary of Implementation

We designed and implemented a hardware-in-the-loop (HIL) calibration system consisting of:
1. **Signal Distortion Simulation**: A host Python script (`host_app.py`) that generates a high-frequency analog input and injects second- and third-order non-linear harmonic distortions to simulate real-world ADC limitations.
2. **Interface Bridge**: An RP2040 microcontroller script (`rp2040_bus.py`) that receives raw 12-bit ADC data over USB CDC and routes it to the FPGA over a 4-bit bidirectional parallel bus. It uses direct SIO register manipulation to meet timing requirements and prevent data transmission bottlenecks.
3. **Polynomial Engine**: A Verilog processor inside the SLG47910 FPGA that zero-centers the input raw code and evaluates the third-order regression correction model using a sequential state machine. A single shared signed multiplier block computes the polynomial factors sequentially to minimize physical macrocell usage.

---

## Test Log Output

The log below shows raw distorted ADC codes injected into the calibration pipeline and the corrected linear values returned by the FPGA:

```text
Streaming data pipeline open to Vicharak RP2040...
Index  | Raw ADC Code   | Calibrated Output 
----------------------------------------------
0      | 2047           | 2047              
1      | 4095           | 3822              
2      | 2015           | 2024              
3      | 471            | 686               
4      | 2112           | 2098              
5      | 4095           | 3822              
6      | 1951           | 1979              
7      | 472            | 686               
8      | 2177           | 2145              
9      | 4095           | 3822              
10     | 1888           | 1919              
11     | 474            | 688               
12     | 2243           | 2210              
13     | 4095           | 3822              
14     | 1825           | 1856              
15     | 477            | 690               
16     | 2309           | 2276              
17     | 4095           | 3822              
18     | 1764           | 1794              
19     | 481            | 692               
20     | 2376           | 2343              
21     | 4095           | 3822              
22     | 1703           | 1733              
23     | 486            | 698               
24     | 2442           | 2409              
25     | 4095           | 3822              
26     | 1644           | 1673              
27     | 492            | 700               
28     | 2509           | 2476              
29     | 4095           | 3822              
30     | 1586           | 1615              
31     | 499            | 702               
32     | 2575           | 2542              
33     | 4095           | 3822              
34     | 1529           | 1557              
35     | 507            | 710               
36     | 2642           | 2608              
37     | 4095           | 3822              
38     | 1473           | 1501              
39     | 516            | 719               
40     | 2707           | 2675              
```
