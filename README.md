# Digital Calibration Engine for High-Speed Data Converters
 
This project implements a digital calibration engine to correct non-linear distortions in high-speed Analog-to-Digital Converters (ADCs). In high-speed mixed-signal front-ends, manufacturing variances, aging, and thermal drift introduce integral non-linearity (INL) and differential non-linearity (DNL), causing harmonic distortions that degrade the signal-to-noise and distortion ratio (SNDR).
 
Instead of deploying large, resource-intensive Look-Up Tables (LUTs) in hardware, this project implements a real-time, resource-optimized polynomial calibration engine directly inside an FPGA fabric to linearize the raw digitizer output.
 
---
 
## Detailed ADC Theory and Distortion Modeling
 
### 1. Fundamentals of Analog-to-Digital Conversion
 
Analog-to-Digital Converters (ADCs) bridge the continuous physical world and discrete-time digital processing systems. The conversion process consists of two primary operations:
 
1. **Sampling**: Discretizing the continuous-time analog input signal $V_{\text{in}}(t)$ at periodic intervals $T_s = 1/f_s$.
2. **Quantization**: Mapping the continuous amplitude of the sampled voltage to one of $2^N$ discrete levels, where $N$ is the resolution (bit-width) of the converter.
Mathematically, the ideal quantization transfer function mapping the input voltage $V_{\text{in}}$ to a digital code $D$ is:
 
$$
D = \text{round}\left( \frac{V_{\text{in}} - V_{\text{ref-}}}{V_{\text{ref+}} - V_{\text{ref-}}} \cdot (2^N - 1) \right)
$$
 
Because a range of continuous input voltages maps to the same digital code, quantization introduces an inherent error known as **Quantization Noise**. For an ideal converter with step size $\Delta = \text{LSB}$ (Least Significant Bit), the quantization error $e_q$ is bounded by $\pm \frac{\Delta}{2}$. Assuming a uniform probability density function for $e_q$ over this interval, the quantization noise power is:
 
$$
\sigma_q^2 = \frac{1}{\Delta} \int_{-\Delta/2}^{\Delta/2} e^2 \, de = \frac{\Delta^2}{12}
$$
 
For a full-scale sinusoidal input with peak-to-peak amplitude equal to the input range of the ADC, the signal power is $P_{\text{signal}} = \frac{(2^N \cdot \Delta / 2)^2}{2} = \frac{2^{2N} \Delta^2}{8}$. The theoretical maximum **Signal-to-Noise Ratio (SNR)** of an ideal $N$-bit ADC is derived as:
 
$$
\text{SNR}_{\text{ideal}} = 10 \log_{10}\left( \frac{P_{\text{signal}}}{\sigma_q^2} \right) = 10 \log_{10}\left( \frac{3 \cdot 2^{2N}}{2} \right) \approx 6.02 \cdot N + 1.76 \text{ dB}
$$
 
---
 
### 2. Physical Sources of ADC Non-Linearity (The "Why")
 
Real-world ADCs deviate from this ideal stair-step transfer function. Physical and material limitations in silicon fabrication introduce static and dynamic non-linearities:
 
* **Manufacturing Tolerances & Mismatches**:
  * *Flash ADCs*: Resistor ladder network tolerances directly cause unequal reference voltages for the comparator array.
  * *Successive Approximation Register (SAR) ADCs*: Mismatches in the weighted capacitor array (due to variations in oxide thickness and etching during fabrication) alter the binary weights of the DAC, resulting in uneven steps.
  * *Pipeline ADCs*: Gain errors in stage residue amplifiers (caused by finite open-loop op-amp gain and capacitor mismatch) degrade transfer characteristics between stages.
* **Active Component Imperfections**:
  * Comparator input offset voltages shift transition thresholds.
  * Non-linear input capacitances and switch charge injection introduce signal-dependent charge redistribution.
* **Environmental and Dynamic Drift**:
  * *Thermal Drift*: Temperature gradients change resistor values and transistor transconductance ($g_m$) dynamically.
  * *Aging*: Dielectric relaxation and carrier injection degrade capacitor matching over time.
These imperfections manifest as static errors:
 
* **Differential Non-Linearity (DNL)**: The deviation of an actual analog step width from the ideal 1 LSB value. If $\text{DNL}_i \le -1 \text{ LSB}$, the step width shrinks to zero, causing a **missing code** (the digital output skips that code entirely).
* **Integral Non-Linearity (INL)**: The cumulative sum of DNL errors up to code $i$, representing the deviation of the actual transfer function from a straight line.
---
 
### 3. Mathematics of Harmonic Distortion
 
Static non-linearities warp the input waveform. If we model the non-linear transfer function as a Taylor/Power Series expansion about the zero-point:
 
$$
V_{\text{distorted}} = c_0 + c_1 V_{\text{in}} + c_2 V_{\text{in}}^2 + c_3 V_{\text{in}}^3 + \mathcal{O}(V_{\text{in}}^4)
$$
 
Let a pure, single-tone sinusoidal input signal be:
 
$$
V_{\text{in}}(t) = A \cos(\omega t)
$$
 
Substituting $V_{\text{in}}(t)$ into the power series:
 
$$
V_{\text{distorted}}(t) = c_0 + c_1 A \cos(\omega t) + c_2 A^2 \cos^2(\omega t) + c_3 A^3 \cos^3(\omega t)
$$
 
Using trigonometric power-reduction identities:
 
$$
\begin{aligned}
\cos^2(\omega t) &= \frac{1 + \cos(2\omega t)}{2} \\
\cos^3(\omega t) &= \frac{3\cos(\omega t) + \cos(3\omega t)}{4}
\end{aligned}
$$
 
Expanding and grouping terms:
 
$$
V_{\text{distorted}}(t) = \underbrace{\left( c_0 + \frac{c_2 A^2}{2} \right)}_{\text{DC Offset Shift}} + \underbrace{\left( c_1 A + \frac{3 c_3 A^3}{4} \right) \cos(\omega t)}_{\text{Fundamental Term (Gain Compression/Expansion)}} + \underbrace{\frac{c_2 A^2}{2} \cos(2\omega t)}_{\text{Second Harmonic (HD2)}} + \underbrace{\frac{c_3 A^3}{4} \cos(3\omega t)}_{\text{Third Harmonic (HD3)}}
$$
 
From this derivation, we observe three critical physical phenomena:
 
1. **DC Offset Shift**: Second-order non-linearities ($c_2$) generate a static DC bias shift proportional to the input power ($A^2$).
2. **Fundamental Gain Alteration**: The third-order coefficient ($c_3$) directly scales the fundamental amplitude. If $c_3 < 0$, it causes **gain compression** at higher amplitudes; if $c_3 > 0$, it causes **gain expansion**.
3. **Spurious Harmonic Tones**:
   * $c_2$ generates the second harmonic ($2\omega$), resulting in Second Harmonic Distortion (HD2).
   * $c_3$ generates the third harmonic ($3\omega$), resulting in Third Harmonic Distortion (HD3).
In the frequency domain, these harmonics appear as spurious spikes (spurs) that degrade the **Signal-to-Noise and Distortion Ratio (SNDR)**:
 
$$
\text{SNDR} = 10 \log_{10}\left( \frac{P_{\text{fundamental}}}{P_{\text{noise}} + \sum P_{\text{harmonics}}} \right)
$$
 
---
 
### 4. Mathematical Calibration via Polynomial Inversion
 
To linearize the digitizer, we must apply a digital correction filter that implements the mathematical inverse of the distortion function.
Suppose the physical ADC injects second- and third-order non-linearities:
 
$$
u = v + \alpha_2 v^2 + \alpha_3 v^3
$$
 
where $v$ is the ideal signal and $u$ is the distorted output. We seek a digital correction function $g(u)$ that recovers $v$:
 
$$
y = g(u) = \beta_1 u + \beta_2 u^2 + \beta_3 u^3 \approx v
$$
 
We can find the inverse coefficients $\beta_k$ analytically by substituting $u$ into the expression for $y$:
 
$$
\begin{aligned}
y &= \beta_1 (v + \alpha_2 v^2 + \alpha_3 v^3) + \beta_2 (v + \alpha_2 v^2 + \alpha_3 v^3)^2 + \beta_3 (v + \alpha_2 v^2 + \alpha_3 v^3)^3 \\
&= \beta_1 v + (\beta_1 \alpha_2 + \beta_2) v^2 + (\beta_1 \alpha_3 + 2 \beta_2 \alpha_2 + \beta_3) v^3 + \mathcal{O}(v^4)
\end{aligned}
$$
 
For $y = v$ to hold, the higher-order terms of $v$ must vanish. Equating coefficients:
 
* $v^1 \text{ term}: \beta_1 = 1$
* $v^2 \text{ term}: \beta_1 \alpha_2 + \beta_2 = 0 \implies \beta_2 = -\alpha_2$
* $v^3 \text{ term}: \beta_1 \alpha_3 + 2 \beta_2 \alpha_2 + \beta_3 = 0 \implies \beta_3 = 2 \alpha_2^2 - \alpha_3$
In our system, we inject distortions mathematically with $\alpha_2 = 0.15$ and $\alpha_3 = -0.08$:
 
$$
V_{\text{distorted}} = V_{\text{ideal}} + 0.15 V_{\text{ideal}}^2 - 0.08 V_{\text{ideal}}^3
$$
 
Solving for the analytical inverse coefficients:
 
* $\beta_1 = 1$
* $\beta_2 = -0.15$
* $\beta_3 = 2(0.15)^2 - (-0.08) = 0.045 + 0.08 = 0.125$
This yields the continuous-domain mathematical inverse:
 
$$
y(u) = u - 0.15 u^2 + 0.125 u^3
$$
 
---
 
### 5. Least-Squares Polynomial Calibration Fitting
 
Although the analytical Taylor series expansion provides a local inverse near zero, its accuracy degrades at large signal amplitudes. To achieve optimal performance across the full dynamic range $[-1.0, 1.0]$ (which translates to the digital integer space $[0, 4095]$), we use a least-squares regression approach to fit a global polynomial correction model.
 
#### Problem Formulation
 
We frame the calibration as a polynomial curve-fitting task:
 
* **Input Feature ($x$)**: The zero-centered raw 12-bit ADC code:
  $$
  x = D_{\text{raw}} - 2048 \quad \in [-2048, 2047]
  $$
* **Target ($y_{\text{ideal}}$)**: The zero-centered ideal 12-bit output:
  $$
  y_{\text{ideal}} = 2048 \cdot V_{\text{ideal}} \quad \in [-2048, 2047]
  $$
* **Model Function ($h_{\mathbf{w}}(x)$)**: A third-order polynomial:
  $$
  h_{\mathbf{w}}(x) = w_0 + w_1 x + w_2 x^2 + w_3 x^3
  $$
#### Loss Function & Optimization
 
We define our loss function as the Mean Squared Error (MSE) over a dataset of $M$ samples:
 
$$
J(\mathbf{w}) = \frac{1}{M} \sum_{i=1}^M \left( y_{\text{ideal}}^{(i)} - h_{\mathbf{w}}(x^{(i)}) \right)^2
$$
 
To find the globally optimal weights $\mathbf{w} = [w_0, w_1, w_2, w_3]^T$ that minimize $J(\mathbf{w})$, we solve the **Least-Squares Normal Equation**:
 
$$
\mathbf{w} = \left(\mathbf{X}^T \mathbf{X}\right)^{-1} \mathbf{X}^T \mathbf{y}_{\text{ideal}}
$$
 
where $\mathbf{X}$ is the $M \times 4$ Vandermonde design matrix:
 
$$
\mathbf{X} = \begin{bmatrix}
1 & x^{(1)} & (x^{(1)})^2 & (x^{(1)})^3 \\
1 & x^{(2)} & (x^{(2)})^2 & (x^{(2)})^3 \\
\vdots & \vdots & \vdots & \vdots \\
1 & x^{(M)} & (x^{(M)})^2 & (x^{(M)})^3
\end{bmatrix}
$$
 
Solving this globally over the full-scale sinusoidal swing balances the fitting errors across the entire input code range. The resulting optimal floating-point weights are:
 
* $w_0 \approx -0.02929$ LSB (corrects for static DC shift)
* $w_1 \approx 1.20117$ (scales the linear gain)
* $w_2 \approx -2.238 \cdot 10^{-5}$ (cancels second-order harmonic distortions)
* $w_3 \approx 4.453 \cdot 10^{-9}$ (cancels third-order harmonic distortions)
---
 
### 6. Fixed-Point Quantization and Scaling Mathematics
 
Implementing floating-point arithmetic directly inside an FPGA requires significant logic resources and introduces latency. Instead, we map the floating-point weights $w$ to fixed-point integer coefficients using binary scaling factors (Q-format representation).
 
We choose dynamic fractional scaling for each degree to maximize the dynamic range and prevent underflow of small coefficients:
 
| Coefficient | Q-format | Scaling | Computation | Result |
|---|---|---|---|---|
| `COEFF_C0` ($w_0$) | Q0 | $2^0$ | `round(w_0 * 2^0)` | `-120` (`0xFF88`, 16-bit two's complement) |
| `COEFF_C1` ($w_1$) | Q12 | $2^{12} = 4096$ | `round(w_1 * 4096) = round(1.20117 * 4096)` | `4920` (`0x1338`) |
| `COEFF_C2` ($w_2$) | Q24 | $2^{24} = 16{,}777{,}216$ | `round(w_2 * 2^24) = round(-3.755e-5 * 2^24)` | `-630` (`0xFD8A`) |
| `COEFF_C3` ($w_3$) | Q36 | $2^{36} \approx 6.8719 \times 10^{10}$ | `round(w_3 * 2^36) = round(3.056e-9 * 6.8719e10)` | `210` (`0x00D2`) |
 
#### Step-by-Step FPGA Register Math
 
Let's trace how the Verilog module [adc_calibrator.v](rtl/adc_calibrator.v) evaluates this polynomial using intermediate shifts to keep signals bounded within 13-bit signed registers:
 
1. **Zero-Centering the Input**
```
   x_reg = raw_adc - 2048        // range: [-2048, 2047]
```
 
2. **Sequential Power Multiplication**
   * Compute $x^2$:
```
     x2_reg = (x_reg * x_reg) >> 12
```
     The 13-bit × 13-bit signed multiplication yields a 25-bit product. Shifting right by 12 bits scales it back to a 13-bit signed representation ($x^2 / 2^{12}$).
   * Compute $x^3$:
```
     x3_reg = (x2_reg * x_reg) >> 12
```
     Multiplying $x^2/2^{12}$ (13-bit) by `x_reg` (13-bit) yields a 25-bit product. Shifting right by 12 scales it to $x^3/2^{24}$, stored in the 13-bit signed `x3_reg`.
 
3. **Coefficient Product Generation**
```
   p_1 = COEFF_C1 * x_reg
   p_2 = COEFF_C2 * x2_reg     //  = COEFF_C2 * (x^2 / 2^12)
   p_3 = COEFF_C3 * x3_reg     //  = COEFF_C3 * (x^3 / 2^24)
```
 
   These three intermediate products (`p_1`, `p_2`, `p_3`) are stored in 29-bit signed registers.
 
4. **Parallel Accumulation & Reconstruction**
   The final calibrated output is calculated in a combinational block:
```
   y_scaled_comb = COEFF_C0 + (p_1 >> 12) + (p_2 >> 12) + (p_3 >> 12) + 2048
```
 
   We verify the mathematical scaling of each term:
 
   | Term | Register expression | Simplifies to |
   |---|---|---|
   | 1 | `COEFF_C0` | $w_0$ |
   | 2 | `p_1 / 2^12` | $w_1 x$ |
   | 3 | `p_2 / 2^12` | $w_2 x^2$ |
   | 4 | `p_3 / 2^12` | $w_3 x^3$ |
 
   The scaling aligns perfectly, producing the reconstructed calibrated code. Adding `2048` restores the offset to the standard unsigned 12-bit range $[0, 4095]$.
 
5. **Saturation Logic**
   To prevent overflow wrap-around where values exceeding 4095 wrap around to 0 (causing severe dynamic noise spikes), a clipping block constrains the output code to $[0, 4095]$:
```
   calibrated_adc = max(0, min(4095, y_scaled_comb))
```
 
---

## Hardware-in-the-Loop (HIL) Implementation
 
We designed and implemented a hardware-in-the-loop (HIL) calibration system consisting of:
 
1. **Signal Distortion Simulation**: A Python host application [host_app.py](host_app.py) that simulates high-frequency analog input signals, injects mathematical non-linear harmonic distortions to simulate physical ADC limitations, streams the distorted codes to the microcontroller, and reads back the calibrated results.
2. **Interface Bridge**: An RP2040 microcontroller running [rp2040_bus.py](rp2040_bus.py) that acts as the communication link. To prevent data transmission bottlenecks and maintain high sampling rates, it interfaces with the FPGA over a 4-bit bidirectional parallel bus using direct memory-mapped access to the RP2040 SIO registers (bypassing slow hardware abstraction layers).
3. **Sequential FPGA Polynomial Engine**: A Verilog processor synthesized for the SLG47910 FPGA (using [top.v](rtl/top.v)).
   * [parallel_rx.v](rtl/parallel_rx.v) deserializes raw 12-bit ADC data received in 3 sequential nibbles.
   * [adc_calibrator.v](rtl/adc_calibrator.v) implements a sequential 12-state FSM that performs the polynomial calculations. It uses a single shared signed multiplier block to calculate the coefficients sequentially, reducing the physical microcell count and logic density.
   * [parallel_tx.v](rtl/parallel_tx.v) streams the calibrated 12-bit values back to the RP2040 over the 4-bit parallel bus using strobe synchronization.
---
 
## Hardware-in-the-Loop (HIL) Implementation
 
We designed and implemented a hardware-in-the-loop (HIL) calibration system consisting of:
 
1. **Signal Distortion Simulation**: A Python host application [host_app.py](host_app.py) that simulates high-frequency analog input signals, injects mathematical non-linear harmonic distortions to simulate physical ADC limitations, streams the distorted codes to the microcontroller, and reads back the calibrated results.
2. **Interface Bridge**: An RP2040 microcontroller running [rp2040_bus.py](rp2040_bus.py) that acts as the communication link. To prevent data transmission bottlenecks and maintain high sampling rates, it interfaces with the FPGA over a 4-bit bidirectional parallel bus using direct memory-mapped access to the RP2040 SIO registers (bypassing slow hardware abstraction layers).
3. **Sequential FPGA Polynomial Engine**: A Verilog processor synthesized for the SLG47910 FPGA (using [top.v](rtl/top.v)).
   * [parallel_rx.v](rtl/parallel_rx.v) deserializes raw 12-bit ADC data received in 3 sequential nibbles.
   * [adc_calibrator.v](rtl/adc_calibrator.v) implements a sequential 12-state FSM that performs the polynomial calculations. It uses a single shared signed multiplier block to calculate the coefficients sequentially, reducing the physical microcell count and logic density.
   * [parallel_tx.v](rtl/parallel_tx.v) streams the calibrated 12-bit values back to the RP2040 over the 4-bit parallel bus using strobe synchronization.
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
 
