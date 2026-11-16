import React from "react";
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  Sequence,
  Series,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import {fontFamily} from "./font";

/* ------------------------------------------------------------------ */
/* Configuración: colores, imágenes y duraciones                       */
/* ------------------------------------------------------------------ */

export const FPS = 30;

// Colores de backend/presentacion/index.html (:root) y del panel.
const C = {
  paper: "#F4F4F4", // --fondo
  ink: "#1C1C1E", // --noche, color de los textos
  muted: "#3F3F46", // --suave
  line: "#E4E4E4", // --linea
  accent: "#FF6147", // --coral, naranja principal
  amber: "#D99C13", // --oro
  teal: "#6E6E6E", // texto secundario del panel
  white: "#FFFFFF", // --blanco
};

const BASE = "https://sonoperation.com";
const ASSETS = {
  logo: staticFile("isotipo.png"),
  panel: `${BASE}/medios/panel.png`,
};

// Duraciones mínimas (frames). Si hay audio, se alargan solas (ver Root.tsx).
export const DEFAULT_SCENES = {
  intro: 120,
  plan: 240,
  field: 420,
  quality: 300,
  modules: 240,
  demo: 150,
  closing: 150,
};
export type SceneKey = keyof typeof DEFAULT_SCENES;
export type SonDemoProps = {scenes: Record<SceneKey, number>};

/* ------------------------------------------------------------------ */
/* Utilidades                                                          */
/* ------------------------------------------------------------------ */

const clamp = {extrapolateLeft: "clamp", extrapolateRight: "clamp"} as const;

const usePop = (delay = 0, damping = 200) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return spring({frame: frame - delay, fps, config: {damping}});
};

const Scene: React.FC<{d: number; audio?: SceneKey; children: React.ReactNode}> = ({
  d,
  audio,
  children,
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 12, d - 12, d], [0, 1, 1, 0], clamp);
  return (
    <AbsoluteFill style={{opacity}}>
      {audio ? (
        <Sequence from={12}>
          <Audio src={staticFile(`audio/${audio}.mp3`)} />
        </Sequence>
      ) : null}
      {children}
    </AbsoluteFill>
  );
};

const Background: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{backgroundColor: C.paper}}>
      <AbsoluteFill
        style={{
          backgroundImage: `linear-gradient(${C.line} 1px, transparent 1px), linear-gradient(90deg, ${C.line} 1px, transparent 1px)`,
          backgroundSize: "80px 80px",
          backgroundPosition: `${frame * 0.25}px ${frame * 0.25}px`,
          opacity: 0.45,
        }}
      />
    </AbsoluteFill>
  );
};

/* ------------------------------------------------------------------ */
/* Piezas reutilizables                                                */
/* ------------------------------------------------------------------ */

const StepText: React.FC<{n: string; title: string; text: string; width?: number}> = ({
  n,
  title,
  text,
  width = 640,
}) => {
  const a = usePop(0);
  const b = usePop(8);
  const c = usePop(16);
  return (
    <div style={{width, fontFamily, color: C.ink}}>
      <div
        style={{
          opacity: a,
          transform: `translateY(${(1 - a) * 24}px)`,
          fontSize: 40,
          fontWeight: 800,
          color: C.accent,
          marginBottom: 12,
        }}
      >
        {n}
      </div>
      <div
        style={{
          opacity: b,
          transform: `translateY(${(1 - b) * 24}px)`,
          fontSize: 84,
          fontWeight: 800,
          lineHeight: 1.02,
          letterSpacing: -2,
          marginBottom: 24,
        }}
      >
        {title}
      </div>
      <div
        style={{
          opacity: c,
          transform: `translateY(${(1 - c) * 24}px)`,
          fontSize: 34,
          lineHeight: 1.4,
          color: C.muted,
          fontWeight: 400,
        }}
      >
        {text}
      </div>
    </div>
  );
};

const BrowserFrame: React.FC<{src: string; w: number; h: number; zoom: number}> = ({
  src,
  w,
  h,
  zoom,
}) => (
  <div
    style={{
      width: w,
      borderRadius: 20,
      overflow: "hidden",
      background: C.white,
      boxShadow: "0 30px 80px rgba(15,42,61,0.22)",
      border: `1px solid ${C.line}`,
      fontFamily,
    }}
  >
    <div
      style={{
        height: 52,
        background: "#E9EEF0",
        display: "flex",
        alignItems: "center",
        padding: "0 20px",
        gap: 10,
      }}
    >
      {["#F28B82", "#F2C94C", "#6FCF97"].map((col) => (
        <div key={col} style={{width: 14, height: 14, borderRadius: 7, background: col}} />
      ))}
      <div
        style={{
          marginLeft: 20,
          fontSize: 20,
          color: C.muted,
          background: C.white,
          borderRadius: 8,
          padding: "6px 18px",
        }}
      >
        sonoperation.com/panel
      </div>
    </div>
    <div style={{width: w, height: h, overflow: "hidden"}}>
      <Img
        src={src}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
          objectPosition: "top left",
          transform: `scale(${zoom})`,
          transformOrigin: "top left",
        }}
      />
    </div>
  </div>
);

const Check: React.FC<{delay: number; label: string}> = ({delay, label}) => {
  const p = usePop(delay, 14);
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 20,
        opacity: p,
        transform: `translateX(${(1 - p) * 30}px)`,
        fontFamily,
        fontSize: 36,
        fontWeight: 600,
        color: C.ink,
      }}
    >
      <svg width="48" height="48" viewBox="0 0 48 48">
        <circle cx="24" cy="24" r="22" fill={C.accent} />
        <path
          d="M14 25 l8 8 l14 -16"
          fill="none"
          stroke="#fff"
          strokeWidth="5"
          strokeLinecap="round"
          strokeLinejoin="round"
          pathLength={1}
          strokeDasharray={1}
          strokeDashoffset={1 - p}
        />
      </svg>
      {label}
    </div>
  );
};

const Pill: React.FC<{delay: number; label: string; active: boolean}> = ({delay, label, active}) => {
  const p = usePop(delay, 14);
  return (
    <div
      style={{
        fontFamily,
        fontSize: 28,
        fontWeight: 600,
        padding: "12px 26px",
        borderRadius: 999,
        background: active ? C.ink : C.white,
        color: active ? C.white : C.ink,
        border: `2px solid ${C.ink}`,
        opacity: p,
        transform: `scale(${0.9 + p * 0.1})`,
      }}
    >
      {label}
    </div>
  );
};

/* ------------------------------------------------------------------ */
/* Mapa en vivo dentro del celular                                     */
/* ------------------------------------------------------------------ */

const PW = 352; // ancho útil de la pantalla
const PH = 752; // alto útil de la pantalla

const ROUTE: [number, number][] = [
  [50, 690],
  [50, 520],
  [170, 520],
  [170, 350],
  [290, 350],
  [290, 170],
];
const SEG = ROUTE.slice(1).map(([x, y], i) => Math.hypot(x - ROUTE[i][0], y - ROUTE[i][1]));
const ROUTE_LEN = SEG.reduce((a, b) => a + b, 0);

const pointAt = (t: number): [number, number] => {
  let dist = Math.min(Math.max(t, 0), 1) * ROUTE_LEN;
  for (let i = 0; i < SEG.length; i++) {
    if (dist <= SEG[i]) {
      const k = SEG[i] === 0 ? 0 : dist / SEG[i];
      return [
        ROUTE[i][0] + (ROUTE[i + 1][0] - ROUTE[i][0]) * k,
        ROUTE[i][1] + (ROUTE[i + 1][1] - ROUTE[i][1]) * k,
      ];
    }
    dist -= SEG[i];
  }
  return ROUTE[ROUTE.length - 1];
};

const STREETS_X = [50, 110, 170, 230, 290];
const STREETS_Y = [90, 170, 260, 350, 440, 520, 610, 690];
const OTHER_TECHS: [number, number][] = [
  [110, 610],
  [230, 440],
  [230, 260],
  [110, 260],
];

const PhoneMap: React.FC<{d: number}> = ({d}) => {
  const frame = useCurrentFrame();
  const arriveAt = Math.round(d * 0.5);
  const t = interpolate(frame, [20, arriveAt], [0, 1], {
    ...clamp,
    easing: Easing.inOut(Easing.quad),
  });
  const [x, y] = pointAt(t);
  const pulse = (frame % 45) / 45;
  const arrived = t >= 1;
  const arrive = usePop(arriveAt, 14);
  const eta = Math.max(0, Math.ceil(8 * (1 - t)));
  const blink = 0.55 + 0.45 * Math.sin(frame / 6);
  const routePath = ROUTE.map((p) => p.join(",")).join(" ");

  return (
    <div style={{position: "absolute", inset: 0, background: "#1B252D", fontFamily}}>
      <svg width={PW} height={PH} viewBox={`0 0 ${PW} ${PH}`} style={{position: "absolute", inset: 0}}>
        {/* agua */}
        <path d="M-10 60 C 70 110, 130 20, 210 60 S 330 110, 370 50 L 370 -10 L -10 -10 Z" fill="#1D3A52" />
        {/* parques */}
        <rect x="116" y="356" width="48" height="78" rx="10" fill="#1F3A33" />
        <rect x="236" y="526" width="48" height="78" rx="10" fill="#1F3A33" />
        <rect x="56" y="176" width="48" height="78" rx="10" fill="#1F3A33" />
        {/* calles */}
        {STREETS_X.map((sx) => (
          <line key={`x${sx}`} x1={sx} y1={0} x2={sx} y2={PH} stroke="#2C3A45" strokeWidth={7} />
        ))}
        {STREETS_Y.map((sy) => (
          <line key={`y${sy}`} x1={0} y1={sy} x2={PW} y2={sy} stroke="#2C3A45" strokeWidth={7} />
        ))}
        {/* ruta completa tenue y recorrido */}
        <polyline
          points={routePath}
          fill="none"
          stroke={C.accent}
          strokeOpacity={0.3}
          strokeWidth={8}
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeDasharray="2 14"
        />
        <polyline
          points={routePath}
          fill="none"
          stroke={C.accent}
          strokeWidth={8}
          strokeLinecap="round"
          strokeLinejoin="round"
          pathLength={1}
          strokeDasharray={1}
          strokeDashoffset={1 - t}
        />
        {/* otros técnicos */}
        {OTHER_TECHS.map(([ox, oy], i) => (
          <g key={i} transform={`translate(${ox + Math.sin(frame / 40 + i * 2) * 5}, ${oy + Math.cos(frame / 47 + i) * 5})`}>
            <circle r={11} fill={C.teal} fillOpacity={0.25} />
            <circle r={6} fill={C.teal} stroke="#1B252D" strokeWidth={2} />
          </g>
        ))}
        {/* destino */}
        <g transform="translate(290,170)">
          <circle r={20} fill={C.amber} fillOpacity={0.25} />
          <circle r={10} fill={C.amber} stroke="#fff" strokeWidth={3} />
        </g>
        {/* técnico principal */}
        <g transform={`translate(${x}, ${y})`}>
          <circle r={14 + pulse * 26} fill={C.accent} fillOpacity={0.45 * (1 - pulse)} />
          <circle r={11} fill={C.accent} stroke="#fff" strokeWidth={4} />
        </g>
      </svg>

      {/* tarjeta superior */}
      <div
        style={{
          position: "absolute",
          top: 18,
          left: 16,
          right: 16,
          padding: "14px 16px",
          borderRadius: 16,
          background: "rgba(15,24,30,0.94)",
          color: "#fff",
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <div>
          <div style={{fontSize: 22, fontWeight: 800}}>
            {arrived ? "Técnico en el sitio" : "Técnico en camino"}
          </div>
          <div style={{fontSize: 17, color: "#9FB1BF", marginTop: 2}}>
            {arrived ? "Servicio iniciado" : `Llegada estimada: ${eta} min`}
          </div>
        </div>
        <div style={{display: "flex", alignItems: "center", gap: 8, fontSize: 17, fontWeight: 600}}>
          <div style={{width: 10, height: 10, borderRadius: 5, background: C.accent, opacity: blink}} />
          En vivo
        </div>
      </div>

      {/* tarjeta inferior al llegar */}
      <div
        style={{
          position: "absolute",
          bottom: 20,
          left: 16,
          right: 16,
          padding: "14px 16px",
          borderRadius: 16,
          background: "rgba(15,24,30,0.94)",
          color: "#fff",
          display: "flex",
          alignItems: "center",
          gap: 14,
          opacity: arrive,
          transform: `translateY(${(1 - arrive) * 30}px)`,
        }}
      >
        <svg width="38" height="38" viewBox="0 0 48 48">
          <circle cx="24" cy="24" r="22" fill={C.accent} />
          <path d="M14 25 l8 8 l14 -16" fill="none" stroke="#fff" strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <div>
          <div style={{fontSize: 20, fontWeight: 800}}>Llegada registrada</div>
          <div style={{fontSize: 16, color: "#9FB1BF"}}>Presencia validada por GPS</div>
        </div>
      </div>
    </div>
  );
};

/* ------------------------------------------------------------------ */
/* Escenas                                                             */
/* ------------------------------------------------------------------ */

const Intro: React.FC<{d: number}> = ({d}) => {
  const logo = usePop(0, 12);
  const l1 = usePop(14);
  const l2 = usePop(24);
  const sub = usePop(44);
  return (
    <Scene d={d} audio="intro">
      <AbsoluteFill style={{padding: "0 160px", justifyContent: "center", fontFamily}}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 24,
            marginBottom: 70,
            transform: `scale(${0.8 + logo * 0.2})`,
            opacity: logo,
            transformOrigin: "left center",
          }}
        >
          <Img src={ASSETS.logo} style={{height: 96, width: "auto"}} />
          <div style={{fontSize: 44, fontWeight: 800, color: C.ink}}>
            SON <span style={{fontWeight: 400, color: C.muted}}>Operation Platform</span>
          </div>
        </div>
        <div
          style={{
            fontSize: 120,
            fontWeight: 800,
            lineHeight: 1.02,
            letterSpacing: -4,
            color: C.ink,
            maxWidth: 1500,
          }}
        >
          <div style={{opacity: l1, transform: `translateY(${(1 - l1) * 40}px)`}}>
            La gestión de sus operaciones técnicas,
          </div>
          <div style={{opacity: l2, transform: `translateY(${(1 - l2) * 40}px)`}}>
            simplificada y bajo control
          </div>
        </div>
        <div
          style={{
            marginTop: 44,
            fontSize: 38,
            color: C.muted,
            opacity: sub,
            maxWidth: 1300,
            lineHeight: 1.4,
          }}
        >
          Digitalice, coordine y audite el trabajo de sus equipos en terreno.
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

const Plan: React.FC<{d: number}> = ({d}) => {
  const frame = useCurrentFrame();
  const zoom = interpolate(frame, [0, d], [1, 1.08], {...clamp, easing: Easing.inOut(Easing.quad)});
  const slide = usePop(6, 18);
  const start = Math.round(d * 0.4);
  const step = Math.round(d * 0.15);
  const active = Math.min(2, Math.floor(Math.max(0, frame - start) / step));
  return (
    <Scene d={d} audio="plan">
      <AbsoluteFill style={{flexDirection: "row", alignItems: "center", padding: "0 120px", gap: 80}}>
        <StepText
          n="01"
          title="Planificación"
          text="Asigne visitas, clientes y listas de verificación desde el panel central."
          width={600}
        />
        <div
          style={{
            flex: 1,
            display: "flex",
            flexDirection: "column",
            gap: 30,
            alignItems: "flex-start",
            transform: `translateX(${(1 - slide) * 120}px)`,
            opacity: slide,
          }}
        >
          <BrowserFrame src={ASSETS.panel} w={1060} h={600} zoom={zoom} />
          <div style={{display: "flex", gap: 16}}>
            {["Agenda en vivo", "Mapa de técnicos", "Tablero de órdenes"].map((t, i) => (
              <Pill key={t} delay={50 + i * 12} label={t} active={frame > start && active === i} />
            ))}
          </div>
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

const Field: React.FC<{d: number}> = ({d}) => {
  const frame = useCurrentFrame();
  const phone = usePop(4, 18);
  const float = Math.sin(frame / 25) * 8;
  return (
    <Scene d={d} audio="field">
      <AbsoluteFill style={{flexDirection: "row", alignItems: "center", padding: "0 160px", gap: 140}}>
        <div
          style={{
            position: "relative",
            width: 380,
            height: 780,
            transform: `translateY(${(1 - phone) * 140 + float}px)`,
            opacity: phone,
          }}
        >
          <div
            style={{
              position: "relative",
              boxSizing: "border-box",
              width: 380,
              height: 780,
              borderRadius: 58,
              border: `14px solid ${C.ink}`,
              overflow: "hidden",
              background: "#1B252D",
              boxShadow: "0 40px 90px rgba(15,42,61,0.3)",
            }}
          >
            <PhoneMap d={d} />
          </div>
        </div>
        <div style={{display: "flex", flexDirection: "column", gap: 56}}>
          <StepText
            n="02"
            title="Ejecución con GPS"
            text="Siga a su técnico en vivo en el mapa y valide su llegada al sitio, con o sin conexión."
            width={900}
          />
          <div style={{display: "flex", flexDirection: "column", gap: 26}}>
            <Check delay={Math.round(d * 0.52)} label="Presencia validada por GPS" />
            <Check delay={Math.round(d * 0.66)} label="Evidencia fotográfica" />
            <Check delay={Math.round(d * 0.8)} label="Firma digital del cliente" />
          </div>
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

const STAR = "M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z";

const Quality: React.FC<{d: number}> = ({d}) => {
  const frame = useCurrentFrame();
  const page = usePop(4, 18);
  const build = interpolate(frame, [20, d * 0.4], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const sig = interpolate(frame, [d * 0.35, d * 0.5], [0, 1], clamp);
  const stamp = usePop(Math.round(d * 0.55), 10);
  const starStart = Math.round(d * 0.68);

  return (
    <Scene d={d} audio="quality">
      <AbsoluteFill style={{flexDirection: "row", alignItems: "center", padding: "0 160px", gap: 150}}>
        <div
          style={{
            position: "relative",
            width: 560,
            height: 760,
            background: C.white,
            borderRadius: 14,
            boxShadow: "0 30px 80px rgba(15,42,61,0.22)",
            border: `1px solid ${C.line}`,
            transform: `translateY(${(1 - page) * 100}px) rotate(${-2 + page * 2}deg)`,
            opacity: page,
            overflow: "hidden",
            fontFamily,
          }}
        >
          <div style={{clipPath: `inset(0 0 ${(1 - build) * 100}% 0)`, height: "100%"}}>
            <div style={{background: C.ink, color: C.white, padding: "28px 36px", fontSize: 34, fontWeight: 800}}>
              Acta técnica
            </div>
            <div style={{padding: "32px 36px"}}>
              {[90, 70, 82, 55].map((w, i) => (
                <div key={i} style={{height: 16, borderRadius: 8, background: C.line, width: `${w}%`, marginBottom: 18}} />
              ))}
              <div style={{display: "flex", gap: 16, margin: "30px 0"}}>
                {[0, 1, 2].map((i) => (
                  <div
                    key={i}
                    style={{
                      flex: 1,
                      height: 130,
                      borderRadius: 10,
                      background: `linear-gradient(135deg, ${C.accent}33, ${C.accent}88)`,
                    }}
                  />
                ))}
              </div>
              {[95, 60].map((w, i) => (
                <div key={i} style={{height: 16, borderRadius: 8, background: C.line, width: `${w}%`, marginBottom: 18}} />
              ))}
              <svg width="300" height="110" viewBox="0 0 300 110" style={{marginTop: 20}}>
                <path
                  d="M10 80 C 40 10, 70 10, 80 60 S 120 100, 140 50 S 190 20, 210 70 S 260 90, 290 40"
                  fill="none"
                  stroke={C.ink}
                  strokeWidth="4"
                  strokeLinecap="round"
                  pathLength={1}
                  strokeDasharray={1}
                  strokeDashoffset={1 - sig}
                />
              </svg>
            </div>
          </div>
          <div
            style={{
              position: "absolute",
              right: 30,
              bottom: 30,
              padding: "10px 22px",
              borderRadius: 10,
              border: `4px solid ${C.accent}`,
              color: C.accent,
              fontSize: 28,
              fontWeight: 800,
              transform: `rotate(-8deg) scale(${0.6 + stamp * 0.4})`,
              opacity: stamp,
            }}
          >
            Validada
          </div>
        </div>

        <div style={{display: "flex", flexDirection: "column", gap: 60}}>
          <StepText
            n="03"
            title="Calidad automática"
            text="Al cerrar el servicio, el acta en PDF llega al cliente con sus fotos y firma. Después, una encuesta de satisfacción."
            width={820}
          />
          <div style={{display: "flex", gap: 14}}>
            {[0, 1, 2, 3, 4].map((i) => {
              const p = usePop(starStart + i * 8, 10);
              return (
                <svg key={i} width="76" height="76" viewBox="0 0 24 24" style={{transform: `scale(${p})`}}>
                  <path d={STAR} fill={C.amber} />
                </svg>
              );
            })}
          </div>
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

const MODULES = [
  {tag: "Programado", title: "Gestión de órdenes y recurrencia", text: "Despacho inteligente con frecuencias programadas."},
  {tag: "En vivo", title: "Agenda y planificación dinámica", text: "Calendario operativo semanal y mensual en vivo."},
  {tag: "Campo", title: "App móvil de campo", text: "Interfaz con y sin conexión, mapas integrados y cronómetro de servicio."},
  {tag: "Automático", title: "Alertas automatizadas", text: "Comunicación directa por correo sobre traslados y llegadas."},
  {tag: "PDF", title: "Generador de informes", text: "Actas técnicas en PDF con fotografías y firmas."},
  {tag: "NPS", title: "Analítica y métricas", text: "Reportes de productividad y satisfacción del cliente."},
];

const Modules: React.FC<{d: number}> = ({d}) => {
  const title = usePop(0);
  const stagger = Math.max(7, Math.round(d * 0.09));
  return (
    <Scene d={d} audio="modules">
      <AbsoluteFill style={{padding: "100px 120px", fontFamily}}>
        <div
          style={{
            fontSize: 78,
            fontWeight: 800,
            letterSpacing: -2,
            color: C.ink,
            marginBottom: 56,
            opacity: title,
            transform: `translateY(${(1 - title) * 20}px)`,
          }}
        >
          Toda su operación en un único ecosistema
        </div>
        <div style={{display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 28}}>
          {MODULES.map((m, i) => {
            const p = usePop(14 + i * stagger);
            return (
              <div
                key={m.title}
                style={{
                  background: C.white,
                  border: `1px solid ${C.line}`,
                  borderRadius: 18,
                  padding: "34px 38px",
                  height: 270,
                  opacity: p,
                  transform: `translateY(${(1 - p) * 30}px)`,
                }}
              >
                <div
                  style={{
                    display: "inline-block",
                    fontSize: 24,
                    fontWeight: 600,
                    color: C.accent,
                    background: `${C.accent}1A`,
                    padding: "6px 16px",
                    borderRadius: 999,
                    marginBottom: 22,
                  }}
                >
                  {m.tag}
                </div>
                <div style={{fontSize: 38, fontWeight: 800, color: C.ink, lineHeight: 1.15, marginBottom: 12}}>
                  {m.title}
                </div>
                <div style={{fontSize: 27, color: C.muted, lineHeight: 1.35}}>{m.text}</div>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

// Pedido de demostración (ahora va antes del cierre)
const Demo: React.FC<{d: number}> = ({d}) => {
  const a = usePop(0);
  const b = usePop(14);
  const c = usePop(30);
  return (
    <Scene d={d} audio="demo">
      <AbsoluteFill style={{padding: "0 160px", justifyContent: "center", fontFamily}}>
        <Img src={ASSETS.logo} style={{height: 110, width: "auto", marginBottom: 50, opacity: a, alignSelf: "flex-start"}} />
        <div
          style={{
            fontSize: 108,
            fontWeight: 800,
            letterSpacing: -3,
            lineHeight: 1.05,
            color: C.ink,
            maxWidth: 1400,
            opacity: b,
            transform: `translateY(${(1 - b) * 40}px)`,
          }}
        >
          Agende una demostración técnica para su equipo
        </div>
        <div style={{marginTop: 60, display: "flex", gap: 70, fontSize: 36, color: C.ink, fontWeight: 600, opacity: c}}>
          <div>sonoperation.com</div>
          <div>sonoperationn@gmail.com</div>
          <div>+54 9 3547 50-6225</div>
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

// Cierre con la frase de la empresa
const Closing: React.FC<{d: number}> = ({d}) => {
  const logo = usePop(0, 12);
  const l1 = usePop(14);
  const name = usePop(40);
  return (
    <Scene d={d} audio="closing">
      <AbsoluteFill style={{padding: "0 160px", justifyContent: "center", fontFamily}}>
        <Img
          src={ASSETS.logo}
          style={{
            height: 150,
            width: "auto",
            marginBottom: 56,
            alignSelf: "flex-start",
            opacity: logo,
            transform: `scale(${0.8 + logo * 0.2})`,
            transformOrigin: "left center",
          }}
        />
        <div
          style={{
            fontSize: 112,
            fontWeight: 800,
            letterSpacing: -3,
            lineHeight: 1.05,
            color: C.ink,
            maxWidth: 1500,
            opacity: l1,
            transform: `translateY(${(1 - l1) * 40}px)`,
          }}
        >
          Sincronización total entre la administración y el campo
        </div>
        <div style={{marginTop: 50, fontSize: 40, color: C.muted, opacity: name}}>
          SON <span style={{color: C.ink, fontWeight: 600}}>Operation Platform</span>
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

/* ------------------------------------------------------------------ */
/* Composición principal                                               */
/* ------------------------------------------------------------------ */

export const SonDemo: React.FC<SonDemoProps> = ({scenes}) => (
  <AbsoluteFill>
    <Background />
    <Series>
      <Series.Sequence durationInFrames={scenes.intro}><Intro d={scenes.intro} /></Series.Sequence>
      <Series.Sequence durationInFrames={scenes.plan}><Plan d={scenes.plan} /></Series.Sequence>
      <Series.Sequence durationInFrames={scenes.field}><Field d={scenes.field} /></Series.Sequence>
      <Series.Sequence durationInFrames={scenes.quality}><Quality d={scenes.quality} /></Series.Sequence>
      <Series.Sequence durationInFrames={scenes.modules}><Modules d={scenes.modules} /></Series.Sequence>
      <Series.Sequence durationInFrames={scenes.demo}><Demo d={scenes.demo} /></Series.Sequence>
      <Series.Sequence durationInFrames={scenes.closing}><Closing d={scenes.closing} /></Series.Sequence>
    </Series>
  </AbsoluteFill>
);
