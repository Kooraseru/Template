FROM node:24.10.0-bookworm-slim@sha256:b8d2197aff9129d16c801a3e3e1b2a873c4946480f5a310f38056df2268c38d9
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --omit=dev && npm cache clean --force
COPY render-png.mjs JetBrainsMono-Regular.ttf ./
RUN mkdir /input /output
CMD ["node", "/app/render-png.mjs"]
