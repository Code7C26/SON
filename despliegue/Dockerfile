# Imagen del servidor de SON (backend + panel web + programa del agente para descargar).
# Lo arma publicar.ps1 en la carpeta app/ del servidor; no hace falta tocarlo.
FROM node:22-alpine
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY index.js ./
COPY src ./src
COPY assets ./assets
COPY sql ./sql
COPY presentacion ./presentacion
COPY panel ./panel
COPY tecnico ./tecnico
COPY descargas ./descargas

ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "index.js"]
