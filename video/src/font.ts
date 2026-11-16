// Tipografías de SON: Plus Jakarta Sans para títulos e Inter para el resto.
// Los .ttf son los mismos que usan las apps (son_admin/assets/fonts).
// El video usa pesos 400, 600 y 800: 800 carga Bold (700), el más cercano.
import {continueRender, delayRender, staticFile} from "remotion";

const archivos = [
  {family: "Inter", file: "fonts/Inter-Regular.ttf", weight: "400"},
  {family: "Inter", file: "fonts/Inter-SemiBold.ttf", weight: "600"},
  {family: "Inter", file: "fonts/Inter-Bold.ttf", weight: "800"},
  {family: "Plus Jakarta Sans", file: "fonts/PlusJakartaSans-Regular.ttf", weight: "400"},
  {family: "Plus Jakarta Sans", file: "fonts/PlusJakartaSans-SemiBold.ttf", weight: "600"},
  {family: "Plus Jakarta Sans", file: "fonts/PlusJakartaSans-Bold.ttf", weight: "800"},
];

if (typeof document !== "undefined") {
  const handle = delayRender("Cargando Inter y Plus Jakarta Sans");
  Promise.all(
    archivos.map(({family, file, weight}) => {
      const face = new FontFace(family, `url(${staticFile(file)}) format("truetype")`, {
        weight,
        style: "normal",
      });
      return face.load().then((loaded) => {
        document.fonts.add(loaded);
      });
    }),
  )
    .then(() => continueRender(handle))
    .catch((error) => {
      console.error(error);
      continueRender(handle);
    });
}

// Texto general (Inter).
export const fontFamily = `"Inter", sans-serif`;
// Títulos (Plus Jakarta Sans).
export const fontDisplay = `"Plus Jakarta Sans", sans-serif`;
