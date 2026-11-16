import React from "react";
import {Composition, CalculateMetadataFunction, staticFile} from "remotion";
import {getAudioDurationInSeconds} from "@remotion/media-utils";
import {SonDemo, FPS, DEFAULT_SCENES, SceneKey, SonDemoProps} from "./SonDemo";

// Ajusta la duración de cada escena a la duración real de su audio.
// Si un audio no existe todavía, usa la duración por defecto.
const calculateMetadata: CalculateMetadataFunction<SonDemoProps> = async ({props}) => {
  const scenes = {...props.scenes};
  for (const key of Object.keys(DEFAULT_SCENES) as SceneKey[]) {
    try {
      const seconds = await getAudioDurationInSeconds(staticFile(`audio/${key}.mp3`));
      // 0,4 s de silencio al inicio + 0,9 s de pausa al final
      scenes[key] = Math.max(DEFAULT_SCENES[key], Math.ceil((seconds + 1.3) * FPS));
    } catch {
      scenes[key] = DEFAULT_SCENES[key];
    }
  }
  const total = Object.values(scenes).reduce((a, b) => a + b, 0);
  return {durationInFrames: total, props: {scenes}};
};

export const RemotionRoot: React.FC = () => (
  <Composition
    id="SonDemo"
    component={SonDemo}
    durationInFrames={Object.values(DEFAULT_SCENES).reduce((a, b) => a + b, 0)}
    fps={FPS}
    width={1920}
    height={1080}
    defaultProps={{scenes: DEFAULT_SCENES}}
    calculateMetadata={calculateMetadata}
  />
);
