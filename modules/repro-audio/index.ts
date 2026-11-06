import { requireNativeModule } from "expo-modules-core";

export type PlainTrialResult = {
  progressMs: number | null;
  gapActualMs: number;
  deactivatedAtMs: number | null;
  deactivateError: string | null;
  timeControlStatus: number;
  reason: string | null;
};

type ReproAudioNative = {
  launchArguments(): string[];
  openLog(name: string): void;
  appendLog(line: string): void;
  keepScreenOn(): Promise<void>;
  configurePlainSession(): Promise<void>;
  runPlainTrial(
    uri: string,
    scenario: string,
    gapMs: number,
    deactivate: boolean,
  ): Promise<PlainTrialResult>;
};

export default requireNativeModule<ReproAudioNative>("ReproAudio");
