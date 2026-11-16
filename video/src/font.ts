// Bw Gradual es la fuente del sitio y del panel (archivos .otf propios,
// no está en Google Fonts). Los archivos reales son Regular 400, Medium 500
// y Bold 700. El video usa 400, 600 y 800: 600 carga Medium y 800 carga Bold,
// que son los pesos más cercanos.
import {continueRender, delayRender, staticFile} from "remotion";

const family = "Bw Gradual";

const weights = [
  {file: "fonts/BwGradualDEMO-Regular.otf", weight: "400"},
  {file: "fonts/BwGradualDEMO-Medium.otf", weight: "600"},
  {file: "fonts/BwGradualDEMO-Bold.otf", weight: "800"},
];

if (typeof document !== "undefined") {
  const handle = delayRender("Cargando Bw Gradual");
  Promise.all(
    weights.map(({file, weight}) => {
      const face = new FontFace(family, `url(${staticFile(file)}) format("opentype")`, {
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

export const fontFamily = `"${family}", sans-serif`;
