# bloop

Micro-looper for norns
Insects Theory 2026.

Record a loop up to **30 seconds** long, overdub on it, filter it, slow it down,
reverse it and chop it into pieces with the scrambler.

> **The scrambler is on by default.** To turn it off: tap **K1**, or
> `PARAMS > bloop > scrambler on`.

---

## Install

On norns, from maiden (`;install`) with the repository URL, or copy `bloop.lua` to
`~/dust/code/bloop/bloop.lua` (via SFTP or SMB) and restart from the SELECT menu.
Needs a recent norns firmware (uses `softcut`, `clock`, `keyboard`).

---

## Controls

| Control | Function |
|---|---|
| **ENC1** | `repeats`: loop decay. Also works during playback only |
| **ENC2** | mod A: speed / pitch (0.1 – 2.0) |
| **ENC3** | mod B: low-pass filter cutoff (60 – 12000 Hz) |
| **K2** | tap to advance: rec → play → overdub → play … (from stop: resumes playback) |
| **K3** | stop / play |
| **K1 (hold)** | ALT |
| **K1 (short tap)** | scrambler on / off |

### With ALT (K1 held)

| Control | Function |
|---|---|
| **ALT + K2** | cycle mode (normal → additive → sampler) |
| **ALT + K3 (tap)** | undo (up to 4 levels) |
| **ALT + K3 (hold 0.8 s)** | clear the loop |
| **ALT + ENC1** | loop start point |
| **ALT + ENC2** | loop length / trim |
| **ALT + ENC3** | direction: turn left = reverse, turn right = forward |

A K1 tap toggles the scrambler only if it lasts less than 0.5 s and you did not use it
as ALT (i.e. no other key pressed and no encoder turned while it was held).

---

## USB pedal

A single footswitch that shows up as a USB keyboard. The key is learned on the **first
press**; to reassign it use `PARAMS > pedal: learn key` and press the pedal.

| Gesture | Function |
|---|---|
| **tap** | rec → play → overdub (same as K2) |
| **double tap** during overdub | stop and discard the overdub |
| **hold 0.7 s** | stop (discards the overdub that just started; clears a first take while recording) |
| **hold 2.5 s** | clear the loop |

---

## Modes

- **normal**: the filter only affects what you hear; the recorded loop stays clean.
- **additive**: the filtered signal is re-recorded into the loop on every pass, so the colour builds up.
- **sampler**: each new take replaces the previous one, no overdub.

---

## Features

### Scrambler (on by default)
Splits the loop into N slices and moves the playback head between them.

- **On/off**: short tap on K1, or the `scrambler on` parameter.
- **`scrambler amount`** (-1 … 1, default 0.6):
  - **negative** values = random jumps;
  - **positive** values = fixed (shuffled) sequence that repeats;
  - **0** = no jumps;
  - the absolute value is the probability that a slice gets replaced.
- **`scrambler slices`**: number of slices, 2 / 4 / 8 / 16 (default 8).
- Works in play and overdub, follows start point, trim, speed and reverse.
- The record head stays regular: in *additive* it records what you hear, in *normal*
  the overdub lands in a different spot than what you are listening to.
- **`scr`** appears next to ALT on screen when it is active.

### Looper
- Records up to 30 s; the take closes itself at the buffer limit (`max len`).
- During the first take the speed is fixed at 1, so the length is exact.
- **`quantize loop length`**: off / beat / bar, rounds the length to the clock.
- **Undo** with 4 levels (snapshots taken before each overdub).
- **Start point** and **trim** can be changed without clicks in playback.
- **Reverse** and speed 0.1× – 2×.

### Sound
- **`filter resonance (rq)`**: filter resonance (lower rq = more resonant).
- **`stability (wobble)`**: tape-style speed instability.
- **`loop output level`** (0 – 2): loop output volume.
- **`output compressor`**: system compressor on/off.

### Interface
- 5-second startup animation (a falling drop, ripples and the "bloop" lettering bouncing in); keys and encoders are ignored during the intro.
- Animated reel that spins with the loop's direction and speed; the center dot follows the input level.
- Loop bar with active area and playhead; rec / overdub / play indicators, undo counter (`u1`…`u4`) and temporary messages.

---

## Parameters (PARAMS menu)

| Parameter | Default |
|---|---|
| mode | normal |
| repeats | 1.00 |
| mod a: speed/pitch | 1.00 |
| mod b: filter cutoff | 12000 Hz |
| filter resonance (rq) | 0.60 |
| start point | 0.00 |
| loop length (trim) | 1.00 |
| quantize loop length | off |
| scrambler amount | 0.60 |
| scrambler slices | 8 |
| **scrambler on** | **on** |
| stability (wobble) | 0.00 |
| loop output level | 1.00 |
| output compressor | off |
| pedal: learn key | (action) |

If you save a PSET, the saved value of `scrambler on` takes precedence over the default.

---

