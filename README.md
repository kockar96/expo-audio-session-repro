# expo-audio session deactivation repro

On iOS, expo-audio deactivates the audio session 100 ms after a player pauses or finishes. A `play()` from another player around that moment silently stays paused: no error, `playing` and `isBuffering` are `false`, and `currentTime` stays at 0.

The app runs trials on launch and writes one JSON line per trial. Each trial plays one player until it pauses or finishes, waits a gap from 0 to 300 ms, seeks a second player to 0 and plays it. A stall means the second player's position hasn't moved after 2.5 s.

## Variants

| `--arm` | What runs |
|---|---|
| `E0` | expo-audio |
| `E1` | expo-audio with an idle `keepAudioSessionActive` player |
| `P0` | Plain `AVPlayer` with the same session lifecycle as expo-audio (`modules/repro-audio`) |
| `P1` | Plain `AVPlayer`, no deactivation |
| `E2`, `E3` | Patched expo-audio; see below |

## Run it

Use a physical iPhone. Tested on an iPhone 13 with iOS 27.0.

1. In `app.json`, set `ios.bundleIdentifier` to your own and add `ios.appleTeamId`.
2. Install and build:

   ```bash
   npm install
   npx expo run:ios --device <udid> --configuration Release --no-bundler
   ```

3. Keep the phone unlocked and run a variant. Results land in `out/`:

   ```bash
   scripts/run-arm.sh <udid> <bundle-id> E0 3 e0
   python3 scripts/analyze.py 'out/results-*.jsonl'
   ```

## Results

`results/` holds the raw data from my runs. The gaps deliberately target the window, so rates are far above normal use.

| Variant | Stalls |
|---|---|
| `E0` expo-audio | 24/72 |
| `E1` expo-audio with keeper | 0/144 |
| `P0` plain `AVPlayer`, deactivating | 40/144 |
| `P1` plain `AVPlayer`, no deactivation | 0/72 |

```bash
python3 scripts/analyze.py 'results/results-full*.jsonl'
```

## Patched variants

`patches/expo-audio-instrumentation.patch` timestamps `play()` and the deactivation in expo-audio, and adds two candidate changes selected by `--arm`:

- `E2` cancels a pending deactivation when a newer `play()` arrives.
- `E3` skips the deactivation in `mixWithOthers` mode.

Apply it with `patch -p1 < patches/expo-audio-instrumentation.patch` after `npm install`, then rebuild. `E0` in this build is the baseline: 68/144, with `E2` at 58/144 and `E3` at 2/144.

```bash
python3 scripts/analyze.py 'results/results-fix*.jsonl'
```

## Limits

- One iPhone 13 on iOS 27.0, default audio route, one local clip, no other audio app running.
- `P0` calls `play()`, while expo-audio calls `playImmediately(atRate:)`.
- The first trial after launch can stall for a different reason that I haven't identified.
