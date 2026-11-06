import { Asset } from "expo-asset";
import { type AudioPlayer, createAudioPlayer, setAudioModeAsync } from "expo-audio";
import { useEffect, useState } from "react";
import { Text, View } from "react-native";

import ReproAudio from "./modules/repro-audio";

// E0: expo-audio. E1: expo-audio with an idle keepAudioSessionActive player.
// E2/E3: expo-audio with patches/expo-audio-instrumentation.patch applied.
// P0: plain AVPlayer that deactivates the session like expo-audio. P1: plain AVPlayer, no deactivation.
type Arm = "E0" | "E1" | "E2" | "E3" | "P0" | "P1";
type Scenario = "pause" | "finish";

const GAPS_MS = [0, 30, 60, 80, 90, 100, 110, 120, 140, 170, 200, 300];
const SCENARIOS: Scenario[] = ["pause", "finish"];
const TIMEOUT_MS = 2500;
const SETTLE_MS = 400;

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

const argument = (name: string, fallback: string) => {
  const prefix = `--${name}=`;
  const match = ReproAudio.launchArguments().find((value) => value.startsWith(prefix));
  return match ? match.slice(prefix.length) : fallback;
};

const waitFor = async (condition: () => boolean, timeoutMs: number) => {
  const start = performance.now();
  while (!condition()) {
    if (performance.now() - start > timeoutMs) return false;
    await sleep(5);
  }
  return true;
};

const runExpoTrial = async (uri: string, scenario: Scenario, gapMs: number) => {
  const first: AudioPlayer = createAudioPlayer({ uri });
  const second: AudioPlayer = createAudioPlayer({ uri });
  await waitFor(() => first.isLoaded && second.isLoaded, 2000);

  const finished = new Promise<void>((resolve) => {
    first.addListener("playbackStatusUpdate", (status) => {
      if (status.didJustFinish) resolve();
    });
  });
  first.play();
  if (scenario === "finish") {
    await Promise.race([finished, sleep(3000)]);
  } else {
    await waitFor(() => first.currentTime >= 0.1, 2000);
    first.pause();
  }
  const endedAt = performance.now();
  await sleep(gapMs);
  // The same order Sugu uses: seek first, play once the seek settles.
  await second.seekTo(0);
  const gapActualMs = performance.now() - endedAt;
  const requestedAt = performance.now();
  second.play();
  const progressed = await waitFor(() => second.currentTime > 0, TIMEOUT_MS);
  const result = {
    progressMs: progressed ? performance.now() - requestedAt : null,
    gapActualMs,
    playing: second.playing,
    buffering: second.isBuffering,
    currentTime: second.currentTime,
  };
  first.release();
  second.release();
  return result;
};

export default function App() {
  const [status, setStatus] = useState("starting");

  useEffect(() => {
    const run = async () => {
      const arm = argument("arm", "E0") as Arm;
      const reps = Number(argument("reps", "2"));
      const run_id = argument("run", "manual");
      ReproAudio.openLog(`results-${run_id}.jsonl`);
      await ReproAudio.keepScreenOn();

      const [asset] = await Asset.loadAsync(require("./assets/clip.m4a"));
      const uri = asset.localUri ?? asset.uri;

      if (arm === "P0" || arm === "P1") {
        await ReproAudio.configurePlainSession();
      } else {
        await setAudioModeAsync({ playsInSilentMode: true, interruptionMode: "mixWithOthers" });
      }
      let keeper: AudioPlayer | null = null;
      if (arm === "E1") {
        keeper = createAudioPlayer(null, { keepAudioSessionActive: true });
        keeper.play();
      }

      const trials: { scenario: Scenario; gapMs: number }[] = [];
      for (let i = 0; i < reps; i += 1) {
        for (const scenario of SCENARIOS) {
          for (const gapMs of GAPS_MS) trials.push({ scenario, gapMs });
        }
      }
      trials.sort(() => Math.random() - 0.5);

      for (const [index, { scenario, gapMs }] of trials.entries()) {
        setStatus(`${arm} ${index + 1}/${trials.length}`);
        const result =
          arm === "P0" || arm === "P1"
            ? await ReproAudio.runPlainTrial(uri, scenario, gapMs, arm === "P0")
            : await runExpoTrial(uri, scenario, gapMs);
        ReproAudio.appendLog(JSON.stringify({ arm, scenario, gapMs, ...result }));
        await sleep(SETTLE_MS);
      }
      keeper?.release();
      ReproAudio.appendLog(JSON.stringify({ done: true, arm, trials: trials.length }));
      setStatus(`${arm} done`);
    };
    run().catch((error) => {
      ReproAudio.appendLog(JSON.stringify({ fatal: String(error) }));
      setStatus(`failed: ${String(error)}`);
    });
  }, []);

  return (
    <View style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
      <Text style={{ fontSize: 24 }}>{status}</Text>
    </View>
  );
}
