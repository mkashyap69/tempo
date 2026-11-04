# Cloud Run image for `api` and the jobs (TEMPO_JOB=deletions|recheck).
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY src ./src
RUN npx tsc -p tsconfig.json && npm prune --omit=dev

FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
# Apple's root certificates (public), fetched at build time by CI:
#   curl -O https://www.apple.com/certificateauthority/AppleRootCA-G3.cer (and G2, AppleIncRootCertificate)
COPY apple-roots ./apple-roots
ENV APPLE_ROOT_CA_DIR=/app/apple-roots
USER node
CMD ["node", "dist/index.js"]
